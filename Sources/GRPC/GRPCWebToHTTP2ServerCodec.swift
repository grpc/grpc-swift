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
import NIO
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

    case let .write(part1, part2, promise):
      if let part2 = part2 {
        context.write(self.wrapOutboundOut(part1), promise: nil)
        context.write(self.wrapOutboundOut(part2), promise: promise)
      } else {
        context.write(self.wrapOutboundOut(part1), promise: promise)
      }

    case let .completePromise(promise, result):
      promise?.completeWith(result)
    }
  }
}

extension GRPCWebToHTTP2ServerCodec {
  struct StateMachine {
    /// The current state.
    private var state: State

    fileprivate init(scheme: String) {
      self.state = .idle(scheme: scheme)
    }

    private mutating func withStateAvoidingCoWs(_ body: (inout State) -> Action) -> Action {
      var state: State = ._modifying
      swap(&self.state, &state)
      defer {
        swap(&self.state, &state)
      }
      return body(&state)
    }

    /// Process the inbound `HTTPServerRequestPart`.
    fileprivate mutating func processInbound(
      serverRequestPart: HTTPServerRequestPart,
      allocator: ByteBufferAllocator
    ) -> Action {
      return self.withStateAvoidingCoWs { state in
        state.processInbound(serverRequestPart: serverRequestPart, allocator: allocator)
      }
    }

    /// Process the outbound `HTTP2Frame.FramePayload`.
    fileprivate mutating func processOutbound(
      framePayload: HTTP2Frame.FramePayload,
      promise: EventLoopPromise<Void>?,
      allocator: ByteBufferAllocator
    ) -> Action {
      return self.withStateAvoidingCoWs { state in
        state.processOutbound(framePayload: framePayload, promise: promise, allocator: allocator)
      }
    }

    /// An action to take as a result of interaction with the state machine.
    fileprivate enum Action {
      case none
      case fireChannelRead(HTTP2Frame.FramePayload)
      case write(HTTPServerResponsePart, HTTPServerResponsePart?, EventLoopPromise<Void>?)
      case completePromise(EventLoopPromise<Void>?, Result<Void, Error>)
    }

    fileprivate enum State {
      /// Idle; nothing has been received or sent. The only valid transition is to 'open' when
      /// receiving request headers.
      case idle(scheme: String)

      /// Open; the request headers have been received and we have not sent the end of the response
      /// stream.
      case open(OpenState)

      /// Closed; the response stream (and therefore the request stream) has been closed.
      case closed

      /// Not a real state.
      case _modifying
    }

    fileprivate struct OpenState {
      /// A `ByteBuffer` containing the base64 encoded bytes of the request stream if gRPC Web Text
      /// is being used, `nil` otherwise.
      var requestBuffer: ByteBuffer?

      /// A `CircularBuffer` holding any response messages if gRPC Web Text is being used, `nil`
      /// otherwise.
      var responseBuffer: CircularBuffer<ByteBuffer>?

      /// True if the end of the request stream has been received.
      var requestEndSeen: Bool

      /// True if the response headers have been sent.
      var responseHeadersSent: Bool

      init(isTextEncoded: Bool, allocator: ByteBufferAllocator) {
        self.requestEndSeen = false
        self.responseHeadersSent = false

        if isTextEncoded {
          self.requestBuffer = allocator.buffer(capacity: 0)
          self.responseBuffer = CircularBuffer()
        } else {
          self.requestBuffer = nil
          self.responseBuffer = nil
        }
      }
    }
  }
}

extension GRPCWebToHTTP2ServerCodec.StateMachine.State {
  fileprivate mutating func processInbound(
    serverRequestPart: HTTPServerRequestPart,
    allocator: ByteBufferAllocator
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch serverRequestPart {
    case let .head(head):
      return self.processRequestHead(head, allocator: allocator)
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
    allocator: ByteBufferAllocator
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case let .idle(scheme):
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

      self = .open(.init(isTextEncoded: isWebText, allocator: allocator))
      return .fireChannelRead(.headers(.init(headers: headers)))

    case .open, .closed:
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

    case var .open(state):
      assert(!state.requestEndSeen, "Invalid state: request stream closed")

      if state.requestBuffer == nil {
        // We're not dealing with gRPC Web Text: just forward the buffer.
        return .fireChannelRead(.data(.init(data: .byteBuffer(buffer))))
      }

      if state.requestBuffer!.readableBytes == 0 {
        state.requestBuffer = buffer
      } else {
        state.requestBuffer!.writeBuffer(&buffer)
      }

      let readableBytes = state.requestBuffer!.readableBytes
      // The length of base64 encoded data must be a multiple of 4.
      let bytesToRead = readableBytes - (readableBytes % 4)

      let action: GRPCWebToHTTP2ServerCodec.StateMachine.Action

      if bytesToRead > 0,
        let base64Encoded = state.requestBuffer!.readString(length: bytesToRead),
        let base64Decoded = Data(base64Encoded: base64Encoded) {
        // Recycle the input buffer and restore the request buffer.
        buffer.clear()
        buffer.writeContiguousBytes(base64Decoded)
        action = .fireChannelRead(.data(.init(data: .byteBuffer(buffer))))
      } else {
        action = .none
      }

      self = .open(state)
      return action

    case .closed:
      return .none

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

    case var .open(state):
      assert(!state.requestEndSeen, "Invalid state: already seen end stream ")
      state.requestEndSeen = true
      self = .open(state)

      // Send an empty DATA frame with the end stream flag set.
      let empty = allocator.buffer(capacity: 0)
      return .fireChannelRead(.data(.init(data: .byteBuffer(empty), endStream: true)))

    case .closed:
      return .none

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }
}

// MARK: - Outbound

extension GRPCWebToHTTP2ServerCodec.StateMachine.State {
  private mutating func processResponseHeaders(
    _ payload: HTTP2Frame.FramePayload.Headers,
    promise: EventLoopPromise<Void>?,
    allocator: ByteBufferAllocator
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: haven't received request head")

    case var .open(state):
      let action: GRPCWebToHTTP2ServerCodec.StateMachine.Action

      if state.responseHeadersSent {
        // Headers have been sent, these must be trailers, so end stream must be set.
        assert(payload.endStream)

        if var responseBuffer = state.responseBuffer {
          // We have a response buffer; we're doing gRPC Web Text. Nil out the buffer to avoid CoWs.
          state.responseBuffer = nil

          let buffer = GRPCWebToHTTP2ServerCodec.encodeResponsesAndTrailers(
            &responseBuffer,
            trailers: payload.headers,
            allocator: allocator
          )

          self = .closed
          action = .write(.body(.byteBuffer(buffer)), .end(nil), promise)
        } else {
          // No response buffer; plain gRPC Web.
          let trailers = HTTPHeaders(hpackHeaders: payload.headers)
          self = .closed
          action = .write(.end(trailers), nil, promise)
        }
      } else if payload.endStream {
        // Headers haven't been sent yet and end stream is set: this is a trailers only response
        // so we need to send 'end' as well.
        let head = GRPCWebToHTTP2ServerCodec.makeResponseHead(hpackHeaders: payload.headers)
        self = .closed
        action = .write(.head(head), .end(nil), promise)
      } else {
        // Headers haven't been sent, end stream isn't set. Just send response head.
        state.responseHeadersSent = true
        let head = GRPCWebToHTTP2ServerCodec.makeResponseHead(hpackHeaders: payload.headers)
        self = .open(state)
        action = .write(.head(head), nil, promise)
      }
      return action

    case .closed:
      return .completePromise(promise, .failure(GRPCError.AlreadyComplete()))

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }

  private mutating func processResponseData(
    _ payload: HTTP2Frame.FramePayload.Data,
    promise: EventLoopPromise<Void>?
  ) -> GRPCWebToHTTP2ServerCodec.StateMachine.Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: haven't received request head")

    case var .open(state):
      if state.responseBuffer == nil {
        // Not gRPC Web Text; just write the body.
        return .write(.body(payload.data), nil, promise)
      } else {
        switch payload.data {
        case let .byteBuffer(buffer):
          // '!' is fine, we checked above.
          state.responseBuffer!.append(buffer)

        case .fileRegion:
          preconditionFailure("Unexpected IOData.fileRegion")
        }

        self = .open(state)
        // The response is buffered, we can consider it dealt with.
        return .completePromise(promise, .success(()))
      }

    case .closed:
      return .completePromise(promise, .failure(GRPCError.AlreadyComplete()))

    case ._modifying:
      preconditionFailure("Left in modifying state")
    }
  }
}

// MARK: - Helpers

extension GRPCWebToHTTP2ServerCodec {
  private static func makeResponseHead(hpackHeaders: HPACKHeaders) -> HTTPResponseHead {
    let headers = HTTPHeaders(hpackHeaders: hpackHeaders)

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
