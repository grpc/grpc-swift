/*
 * Copyright 2020, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import struct Foundation.Data
import NIOCore
import NIOHPACK
import NIOHTTP1
import NIOHTTP2

/// A codec for translating between gRPC Web (as HTTP/1) and HTTP/2 frame payloads.
internal final class GRPCWebToHTTP2ServerCodec: ChannelDuplexHandler {
  internal typealias InboundIn = HTTPServerRequestPart
  internal typealias InboundOut = HTTP2Frame.FramePayload

  internal typealias OutboundIn = HTTP2Frame.FramePayload
  internal typealias OutboundOut = HTTPServerResponsePart

  private var stateMachine: StateMachine

  /// Create a gRPC Web to server HTTP/2 codec.
  ///
  /// - Parameter scheme: The value of the ':scheme' pseudo header to insert when converting the
  ///   request headers.
  init(scheme: String) {
    self.stateMachine = StateMachine(scheme: scheme)
  }

  internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let action = self.stateMachine.processInbound(
      serverRequestPart: self.unwrapInboundIn(data),
      allocator: context.channel.allocator
    )
    self.act(on: action, context: context)
  }

  internal func write(
    context: ChannelHandlerContext,
    data: NIOAny,
    promise: EventLoopPromise<Void>?
  ) {
    let action = self.stateMachine.processOutbound(
      framePayload: self.unwrapOutboundIn(data),
      promise: promise,
      allocator: context.channel.allocator
    )
    self.act(on: action, context: context)
  }

  /// Acts on an action returned by the state machine.
  private func act(on action: StateMachine.Action, context: ChannelHandlerContext) {
    switch action {
    case .none:
      ()

    case let .fireChannelRead(payload):
      context.fireChannelRead(self.wrapInboundOut(payload))

    case let .write(write):
      if let additionalPart = write.additionalPart {
        context.write(self.wrapOutboundOut(write.part), promise: nil)
        context.write(self.wrapOutboundOut(additionalPart), promise: write.promise)
      } else {
        context.write(self.wrapOutboundOut(write.part), promise: write.promise)
      }

      if write.closeChannel {
        context.close(mode: .all, promise: nil)
      }

    case let .completePromise(promise, result):
      promise?.completeWith(result)
    }
  }
}

extension GRPCWebToHTTP2ServerCodec {
  internal struct StateMachine {
    /// The current state.
    private var state: State
    private let scheme: String

    internal init(scheme: String) {
      self.state = .idle
      self.scheme = scheme
    }

    /// Process the inbound `HTTPServerRequestPart`.
    internal mutating func processInbound(
      serverRequestPart: HTTPServerRequestPart,
      allocator: ByteBufferAllocator
    ) -> Action {
      return self.state.processInbound(
        serverRequestPart: serverRequestPart,
        scheme: self.scheme,
        allocator: allocator
      )
    }

    /// Process the outbound `HTTP2Frame.FramePayload`.
    internal mutating func processOutbound(
      framePayload: HTTP2Frame.FramePayload,
      promise: EventLoopPromise<Void>?,
      allocator: ByteBufferAllocator
    ) -> Action {
      return self.state.processOutbound(
        framePayload: framePayload,
        promise: promise,
        allocator: allocator
      )
    }

    /// An action to take as a result of interaction with the state machine.
    internal enum Action {
      case none
      case fireChannelRead(HTTP2Frame.FramePayload)
      case write(Write)
      case completePromise(EventLoopPromise<Void>?, Result<Void, Error>)

      internal struct Write {
        internal var part: HTTPServerResponsePart
        internal var additionalPart: HTTPServerResponsePart?
        internal var promise: EventLoopPromise<Void>?
        internal var closeChannel: Bool

        internal init(
          part: HTTPServerResponsePart,
          additionalPart: HTTPServerResponsePart? = nil,
          promise: EventLoopPromise<Void>?,
          closeChannel: Bool
        ) {
          self.part = part
          self.additionalPart = additionalPart
          self.promise = promise
          self.closeChannel = closeChannel
        }
      }
    }

    fileprivate enum State {
      /// Idle; nothing has been received or sent. The only valid transition is to 'fullyOpen' when
      /// receiving request headers.
      case idle

      /// Received request headers. Waiting for the end of request and response streams.
      case fullyOpen(InboundState, OutboundState)

      /// The server has closed the response stream, we may receive other request parts from the client.
      case clientOpenServerClosed(InboundState)

      /// The client has sent everything, the server still needs to close the response stream.
      case clientClosedServerOpen(OutboundState)

      /// Not a real state.
      case _modifying

      private var isModifying: Bool {
        switch self {
        case ._modifying:
          return true
        case .idle, .fullyOpen, .clientClosedServerOpen, .clientOpenServerClosed:
          return false
        }
      }

      private mutating func withStateAvoidingCoWs(_ body: (inout State) -> Action) -> Action {
        self = ._modifying
        defer {
          assert(!self.isModifying)
        }
        return body(&self)
      }
    }

    fileprivate struct InboundState {
      /// A `ByteBuffer` containing the base64 encoded bytes of the request stream if gRPC Web Text
      /// is being used, `nil` otherwise.
      var requestBuffer: ByteBuffer?

      init(isTextEncoded: Bool, allocator: ByteBufferAllocator) {
        self.requestBuffer = isTextEncoded ? allocator.buffer(capacity: 0) : nil
      }
    }

    fileprivate struct OutboundState {
      /// A `CircularBuffer` holding any response messages if gRPC Web Text is being used, `nil`
      /// otherwise.
      var responseBuffer: CircularBuffer<ByteBuffer>?

      /// True if the response headers have been sent.
      var responseHeadersSent: Bool

      /// True if the server should close the connection when this request is done.
      var closeConnection: Bool

      init(isTextEncoded: Bool, closeConnection: Bool) {
        self.responseHeadersSent = false
        self.responseBuffer = isTextEncoded ? CircularBuffer() : nil
        self.closeConnection = closeConnection
      }
    }
  }
}

extension GRPCWebToHTTP2ServerCodec.StateMachine.State {
  fileprivate mutating func processInbound(
    serverRequestPart: HTTPServerRequestPart,
    scheme: String,
    allocator: ByteBufferAllocator
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch serverRequestPart {
    case let .head(head):
      return self.processRequestHead(head, scheme: scheme, allocator: allocator)
    case var .body(buffer):
      return self.processRequestBody(&buffer)
    case .end:
      return self.processRequestEnd(allocator: allocator)
    }
  }

  fileprivate mutating func processOutbound(
    framePayload: HTTP2Frame.FramePayload,
    promise: EventLoopPromise<Void>?,
    allocator: ByteBufferAllocator
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch framePayload {
    case let .headers(payload):
      return self.processResponseHeaders(payload, promise: promise, allocator: allocator)

    case let .data(payload):
      return self.processResponseData(payload, promise: promise)

    case .priority,
         .rstStream,
         .settings,
         .pushPromise,
         .ping,
         .goAway,
         .windowUpdate,
         .alternativeService,
         .origin:
      preconditionFailure("Unsupported frame payload")
    }
  }
}

// MARK: - Inbound

extension GRPCWebToHTTP2ServerCodec.StateMachine.State {
  private mutating func processRequestHead(
    _ head: HTTPRequestHead,
    scheme: String,
    allocator: ByteBufferAllocator
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case .idle:
      return self.withStateAvoidingCoWs { state in
        let normalized = HPACKHeaders(httpHeaders: head.headers, normalizeHTTPHeaders: true)

        // Regular headers need to come after the pseudo headers. Unfortunately, this means we need to
        // allocate a second headers block to use the normalization provided by NIO HTTP/2.
        //
        // TODO: Use API provided by https://github.com/apple/swift-nio-http2/issues/254 to avoid the
        // extra copy.
        var headers = HPACKHeaders()
        headers.reserveCapacity(normalized.count + 4)
        headers.add(name: ":path", value: head.uri)
        headers.add(name: ":method", value: head.method.rawValue)
        headers.add(name: ":scheme", value: scheme)
        if let host = head.headers.first(name: "host") {
          headers.add(name: ":authority", value: host)
        }
        headers.add(contentsOf: normalized)

        // Check whether we're dealing with gRPC Web Text. No need to fully validate the content-type
        // that will be done at the HTTP/2 level.
        let contentType = headers.first(name: GRPCHeaderName.contentType).flatMap(ContentType.init)
        let isWebText = contentType == .some(.webTextProtobuf)

        let closeConnection = head.headers[canonicalForm: "connection"].contains("close")

        state = .fullyOpen(
          .init(isTextEncoded: isWebText, allocator: allocator),
          .init(isTextEncoded: isWebText, closeConnection: closeConnection)
        )
        return .fireChannelRead(.headers(.init(headers: headers)))
      }

    case .fullyOpen, .clientOpenServerClosed, .clientClosedServerOpen:
      preconditionFailure("Invalid state: already received request head")

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  private mutating func processRequestBody(
    _ buffer: inout ByteBuffer
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: haven't received request head")

    case .fullyOpen(var inbound, let outbound):
      return self.withStateAvoidingCoWs { state in
        let action = inbound.processInboundData(buffer: &buffer)
        state = .fullyOpen(inbound, outbound)
        return action
      }

    case var .clientOpenServerClosed(inbound):
      // The server is already done, but it's not our place to drop the request.
      return self.withStateAvoidingCoWs { state in
        let action = inbound.processInboundData(buffer: &buffer)
        state = .clientOpenServerClosed(inbound)
        return action
      }

    case .clientClosedServerOpen:
      preconditionFailure("End of request stream already received")

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  private mutating func processRequestEnd(
    allocator: ByteBufferAllocator
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: haven't received request head")

    case let .fullyOpen(_, outbound):
      return self.withStateAvoidingCoWs { state in
        // We're done with inbound state.
        state = .clientClosedServerOpen(outbound)

        // Send an empty DATA frame with the end stream flag set.
        let empty = allocator.buffer(capacity: 0)
        return .fireChannelRead(.data(.init(data: .byteBuffer(empty), endStream: true)))
      }

    case .clientClosedServerOpen:
      preconditionFailure("End of request stream already received")

    case .clientOpenServerClosed:
      return self.withStateAvoidingCoWs { state in
        // Both sides are closed now, back to idle. Don't forget to pass on the .end, as
        // it's necessary to communicate to the other peers that the response is done.
        state = .idle

        // Send an empty DATA frame with the end stream flag set.
        let empty = allocator.buffer(capacity: 0)
        return .fireChannelRead(.data(.init(data: .byteBuffer(empty), endStream: true)))
      }

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }
}

// MARK: - Outbound

extension GRPCWebToHTTP2ServerCodec.StateMachine.State {
  private mutating func processResponseTrailers(
    _ trailers: HPACKHeaders,
    promise: EventLoopPromise<Void>?,
    allocator: ByteBufferAllocator
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: haven't received request head")

    case .fullyOpen(let inbound, var outbound):
      return self.withStateAvoidingCoWs { state in
        // Double check these are trailers.
        assert(outbound.responseHeadersSent)

        // We haven't seen the end of the request stream yet.
        state = .clientOpenServerClosed(inbound)

        // Avoid CoW-ing the buffers.
        let responseBuffers = outbound.responseBuffer
        outbound.responseBuffer = nil

        return Self.processTrailers(
          responseBuffers: responseBuffers,
          trailers: trailers,
          promise: promise,
          allocator: allocator,
          closeChannel: outbound.closeConnection
        )
      }

    case var .clientClosedServerOpen(state):
      return self.withStateAvoidingCoWs { nextState in
        // Client is closed and now so is the server.
        nextState = .idle

        // Avoid CoW-ing the buffers.
        let responseBuffers = state.responseBuffer
        state.responseBuffer = nil

        return Self.processTrailers(
          responseBuffers: responseBuffers,
          trailers: trailers,
          promise: promise,
          allocator: allocator,
          closeChannel: state.closeConnection
        )
      }

    case .clientOpenServerClosed:
      preconditionFailure("Already seen end of response stream")

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  private static func processTrailers(
    responseBuffers: CircularBuffer<ByteBuffer>?,
    trailers: HPACKHeaders,
    promise: EventLoopPromise<Void>?,
    allocator: ByteBufferAllocator,
    closeChannel: Bool
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    if var responseBuffers = responseBuffers {
      let buffer = GRPCWebToHTTP2ServerCodec.encodeResponsesAndTrailers(
        &responseBuffers,
        trailers: trailers,
        allocator: allocator
      )
      return .write(
        .init(
          part: .body(.byteBuffer(buffer)),
          additionalPart: .end(nil),
          promise: promise,
          closeChannel: closeChannel
        )
      )
    } else {
      // No response buffer; plain gRPC Web.
      let trailers = HTTPHeaders(hpackHeaders: trailers)
      return .write(.init(part: .end(trailers), promise: promise, closeChannel: closeChannel))
    }
  }

  private mutating func processResponseTrailersOnly(
    _ trailers: HPACKHeaders,
    promise: EventLoopPromise<Void>?
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: haven't received request head")

    case let .fullyOpen(inbound, outbound):
      return self.withStateAvoidingCoWs { state in
        // We still haven't seen the end of the request stream.
        state = .clientOpenServerClosed(inbound)

        let head = GRPCWebToHTTP2ServerCodec.makeResponseHead(
          hpackHeaders: trailers,
          closeConnection: outbound.closeConnection
        )

        return .write(
          .init(
            part: .head(head),
            additionalPart: .end(nil),
            promise: promise,
            closeChannel: outbound.closeConnection
          )
        )
      }

    case let .clientClosedServerOpen(outbound):
      return self.withStateAvoidingCoWs { state in
        // We're done, back to idle.
        state = .idle

        let head = GRPCWebToHTTP2ServerCodec.makeResponseHead(
          hpackHeaders: trailers,
          closeConnection: outbound.closeConnection
        )

        return .write(
          .init(
            part: .head(head),
            additionalPart: .end(nil),
            promise: promise,
            closeChannel: outbound.closeConnection
          )
        )
      }

    case .clientOpenServerClosed:
      preconditionFailure("Already seen end of response stream")

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  private mutating func processResponseHeaders(
    _ headers: HPACKHeaders,
    promise: EventLoopPromise<Void>?
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: haven't received request head")

    case .fullyOpen(let inbound, var outbound):
      return self.withStateAvoidingCoWs { state in
        outbound.responseHeadersSent = true
        state = .fullyOpen(inbound, outbound)

        let head = GRPCWebToHTTP2ServerCodec.makeResponseHead(
          hpackHeaders: headers,
          closeConnection: outbound.closeConnection
        )
        return .write(.init(part: .head(head), promise: promise, closeChannel: false))
      }

    case var .clientClosedServerOpen(outbound):
      return self.withStateAvoidingCoWs { state in
        outbound.responseHeadersSent = true
        state = .clientClosedServerOpen(outbound)

        let head = GRPCWebToHTTP2ServerCodec.makeResponseHead(
          hpackHeaders: headers,
          closeConnection: outbound.closeConnection
        )
        return .write(.init(part: .head(head), promise: promise, closeChannel: false))
      }

    case .clientOpenServerClosed:
      preconditionFailure("Already seen end of response stream")

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  private mutating func processResponseHeaders(
    _ payload: HTTP2Frame.FramePayload.Headers,
    promise: EventLoopPromise<Void>?,
    allocator: ByteBufferAllocator
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: haven't received request head")

    case let .fullyOpen(_, outbound),
         let .clientClosedServerOpen(outbound):
      if outbound.responseHeadersSent {
        // Headers have been sent, these must be trailers, so end stream must be set.
        assert(payload.endStream)
        return self.processResponseTrailers(payload.headers, promise: promise, allocator: allocator)
      } else if payload.endStream {
        // Headers haven't been sent yet and end stream is set: this is a trailers only response
        // so we need to send 'end' as well.
        return self.processResponseTrailersOnly(payload.headers, promise: promise)
      } else {
        return self.processResponseHeaders(payload.headers, promise: promise)
      }

    case .clientOpenServerClosed:
      // We've already sent end.
      return .completePromise(promise, .failure(GRPCError.AlreadyComplete()))

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  private static func processResponseData(
    _ payload: HTTP2Frame.FramePayload.Data,
    promise: EventLoopPromise<Void>?,
    state: inout GRPCWebToHTTP2ServerCodec.StateMachine.OutboundState
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    if state.responseBuffer == nil {
      // Not gRPC Web Text; just write the body.
      return .write(.init(part: .body(payload.data), promise: promise, closeChannel: false))
    } else {
      switch payload.data {
      case let .byteBuffer(buffer):
        // '!' is fine, we checked above.
        state.responseBuffer!.append(buffer)

      case .fileRegion:
        preconditionFailure("Unexpected IOData.fileRegion")
      }

      // The response is buffered, we can consider it dealt with.
      return .completePromise(promise, .success(()))
    }
  }

  private mutating func processResponseData(
    _ payload: HTTP2Frame.FramePayload.Data,
    promise: EventLoopPromise<Void>?
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: haven't received request head")

    case .fullyOpen(let inbound, var outbound):
      return self.withStateAvoidingCoWs { state in
        let action = Self.processResponseData(payload, promise: promise, state: &outbound)
        state = .fullyOpen(inbound, outbound)
        return action
      }

    case var .clientClosedServerOpen(outbound):
      return self.withStateAvoidingCoWs { state in
        let action = Self.processResponseData(payload, promise: promise, state: &outbound)
        state = .clientClosedServerOpen(outbound)
        return action
      }

    case .clientOpenServerClosed:
      return .completePromise(promise, .failure(GRPCError.AlreadyComplete()))

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }
}

// MARK: - Helpers

extension GRPCWebToHTTP2ServerCodec {
  private static func makeResponseHead(
    hpackHeaders: HPACKHeaders,
    closeConnection: Bool
  ) -> HTTPResponseHead {
    var headers = HTTPHeaders(hpackHeaders: hpackHeaders)

    if closeConnection {
      headers.add(name: "connection", value: "close")
    }

    // Grab the status, if this is missing we've messed up in another handler.
    guard let statusCode = hpackHeaders.first(name: ":status").flatMap(Int.init) else {
      preconditionFailure("Invalid state: missing ':status' pseudo header")
    }

    return HTTPResponseHead(
      version: .init(major: 1, minor: 1),
      status: .init(statusCode: statusCode),
      headers: headers
    )
  }

  private static func formatTrailers(
    _ trailers: HPACKHeaders,
    allocator: ByteBufferAllocator
  ) -> ByteBuffer {
    // See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md
    let encodedTrailers = trailers.map { name, value, _ in
      "\(name): \(value)"
    }.joined(separator: "\r\n")

    var buffer = allocator.buffer(capacity: 5 + encodedTrailers.utf8.count)
    // Uncompressed trailer byte.
    buffer.writeInteger(UInt8(0x80))
    // Length.
    buffer.writeInteger(UInt32(encodedTrailers.utf8.count))
    // Uncompressed trailers.
    buffer.writeString(encodedTrailers)

    return buffer
  }

  private static func encodeResponsesAndTrailers(
    _ responses: inout CircularBuffer<ByteBuffer>,
    trailers: HPACKHeaders,
    allocator: ByteBufferAllocator
  ) -> ByteBuffer {
    // We need to encode the trailers along with any responses we're holding.
    responses.append(self.formatTrailers(trailers, allocator: allocator))

    let capacity = responses.lazy.map { $0.readableBytes }.reduce(0, +)
    // '!' is fine: responses isn't empty, we just appended the trailers.
    var buffer = responses.popFirst()!

    // Accumulate all the buffers into a single 'Data'. Ideally we wouldn't copy back and forth
    // but this is fine for now.
    var accumulatedData = buffer.readData(length: buffer.readableBytes)!
    accumulatedData.reserveCapacity(capacity)
    while let buffer = responses.popFirst() {
      accumulatedData.append(contentsOf: buffer.readableBytesView)
    }

    // We can reuse the popped buffer.
    let base64Encoded = accumulatedData.base64EncodedString()
    buffer.clear(minimumCapacity: base64Encoded.utf8.count)
    buffer.writeString(base64Encoded)

    return buffer
  }
}

extension GRPCWebToHTTP2ServerCodec.StateMachine.InboundState {
  fileprivate mutating func processInboundData(
    buffer: inout ByteBuffer
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    if self.requestBuffer == nil {
      // We're not dealing with gRPC Web Text: just forward the buffer.
      return .fireChannelRead(.data(.init(data: .byteBuffer(buffer))))
    }

    if self.requestBuffer!.readableBytes == 0 {
      self.requestBuffer = buffer
    } else {
      self.requestBuffer!.writeBuffer(&buffer)
    }

    let readableBytes = self.requestBuffer!.readableBytes
    // The length of base64 encoded data must be a multiple of 4.
    let bytesToRead = readableBytes - (readableBytes % 4)

    let action: GRPCWebToHTTP2ServerCodec.StateMachine.Action

    if bytesToRead > 0,
      let base64Encoded = self.requestBuffer!.readString(length: bytesToRead),
      let base64Decoded = Data(base64Encoded: base64Encoded) {
      // Recycle the input buffer and restore the request buffer.
      buffer.clear()
      buffer.writeContiguousBytes(base64Decoded)
      action = .fireChannelRead(.data(.init(data: .byteBuffer(buffer))))
    } else {
      action = .none
    }

    return action
  }
}

extension HTTPHeaders {
  fileprivate init(hpackHeaders headers: HPACKHeaders) {
    self.init()
    self.reserveCapacity(headers.count)

    // Pseudo-headers are at the start of the block, so drop them and then add the remaining.
    let regularHeaders = headers.drop { name, _, _ in
      name.utf8.first == .some(UInt8(ascii: ":"))
    }.lazy.map { name, value, _ in
      (name, value)
    }

    self.add(contentsOf: regularHeaders)
  }
}
