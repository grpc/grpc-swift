/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Logging
import NIO
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import SwiftProtobuf

/// A gRPC client request message part.
///
/// - Important: This is **NOT** part of the public API. It is declared as
///   `public` because it is used within performance tests.
public enum _GRPCClientRequestPart<Request> {
  /// The 'head' of the request, that is, information about the initiation of the RPC.
  case head(_GRPCRequestHead)

  /// A deserialized request message to send to the server.
  case message(_MessageContext<Request>)

  /// Indicates that the client does not intend to send any further messages.
  case end
}

/// As `_GRPCClientRequestPart` but messages are serialized.
public typealias _RawGRPCClientRequestPart = _GRPCClientRequestPart<ByteBuffer>

/// A gRPC client response message part.
///
/// - Important: This is **NOT** part of the public API.
public enum _GRPCClientResponsePart<Response> {
  /// Metadata received as the server acknowledges the RPC.
  case initialMetadata(HPACKHeaders)

  /// A deserialized response message received from the server.
  case message(_MessageContext<Response>)

  /// The metadata received at the end of the RPC.
  case trailingMetadata(HPACKHeaders)

  /// The final status of the RPC.
  case status(GRPCStatus)
}

/// As `_GRPCClientResponsePart` but messages are serialized.
public typealias _RawGRPCClientResponsePart = _GRPCClientResponsePart<ByteBuffer>

/// - Important: This is **NOT** part of the public API. It is declared as
///   `public` because it is used within performance tests.
public struct _GRPCRequestHead {
  private final class _Storage {
    var method: String
    var scheme: String
    var path: String
    var host: String
    var deadline: NIODeadline
    var encoding: ClientMessageEncoding

    init(
      method: String,
      scheme: String,
      path: String,
      host: String,
      deadline: NIODeadline,
      encoding: ClientMessageEncoding
    ) {
      self.method = method
      self.scheme = scheme
      self.path = path
      self.host = host
      self.deadline = deadline
      self.encoding = encoding
    }

    func copy() -> _Storage {
      return .init(
        method: self.method,
        scheme: self.scheme,
        path: self.path,
        host: self.host,
        deadline: self.deadline,
        encoding: self.encoding
      )
    }
  }

  private var _storage: _Storage
  // Don't put this in storage: it would CoW for every mutation.
  internal var customMetadata: HPACKHeaders

  internal var method: String {
    get {
      return self._storage.method
    }
    set {
      if !isKnownUniquelyReferenced(&self._storage) {
        self._storage = self._storage.copy()
      }
      self._storage.method = newValue
    }
  }

  internal var scheme: String {
    get {
      return self._storage.scheme
    }
    set {
      if !isKnownUniquelyReferenced(&self._storage) {
        self._storage = self._storage.copy()
      }
      self._storage.scheme = newValue
    }
  }

  internal var path: String {
    get {
      return self._storage.path
    }
    set {
      if !isKnownUniquelyReferenced(&self._storage) {
        self._storage = self._storage.copy()
      }
      self._storage.path = newValue
    }
  }

  internal var host: String {
    get {
      return self._storage.host
    }
    set {
      if !isKnownUniquelyReferenced(&self._storage) {
        self._storage = self._storage.copy()
      }
      self._storage.host = newValue
    }
  }

  internal var deadline: NIODeadline {
    get {
      return self._storage.deadline
    }
    set {
      if !isKnownUniquelyReferenced(&self._storage) {
        self._storage = self._storage.copy()
      }
      self._storage.deadline = newValue
    }
  }

  internal var encoding: ClientMessageEncoding {
    get {
      return self._storage.encoding
    }
    set {
      if !isKnownUniquelyReferenced(&self._storage) {
        self._storage = self._storage.copy()
      }
      self._storage.encoding = newValue
    }
  }

  public init(
    method: String,
    scheme: String,
    path: String,
    host: String,
    deadline: NIODeadline,
    customMetadata: HPACKHeaders,
    encoding: ClientMessageEncoding
  ) {
    self._storage = .init(
      method: method,
      scheme: scheme,
      path: path,
      host: host,
      deadline: deadline,
      encoding: encoding
    )
    self.customMetadata = customMetadata
  }
}

extension _GRPCRequestHead {
  internal init(
    scheme: String,
    path: String,
    host: String,
    options: CallOptions,
    requestID: String?
  ) {
    let metadata: HPACKHeaders
    if let requestID = requestID, let requestIDHeader = options.requestIDHeader {
      var customMetadata = options.customMetadata
      customMetadata.add(name: requestIDHeader, value: requestID)
      metadata = customMetadata
    } else {
      metadata = options.customMetadata
    }

    self = _GRPCRequestHead(
      method: options.cacheable ? "GET" : "POST",
      scheme: scheme,
      path: path,
      host: host,
      deadline: options.timeLimit.makeDeadline(),
      customMetadata: metadata,
      encoding: options.messageEncoding
    )
  }
}

/// The type of gRPC call.
public enum GRPCCallType {
  /// Unary: a single request and a single response.
  case unary

  /// Client streaming: many requests and a single response.
  case clientStreaming

  /// Server streaming: a single request and many responses.
  case serverStreaming

  /// Bidirectional streaming: many request and many responses.
  case bidirectionalStreaming

  public var isStreamingRequests: Bool {
    switch self {
    case .clientStreaming, .bidirectionalStreaming:
      return true
    case .unary, .serverStreaming:
      return false
    }
  }

  public var isStreamingResponses: Bool {
    switch self {
    case .serverStreaming, .bidirectionalStreaming:
      return true
    case .unary, .clientStreaming:
      return false
    }
  }
}

// MARK: - GRPCClientChannelHandler

/// A channel handler for gRPC clients which translates HTTP/2 frames into gRPC messages.
///
/// This channel handler should typically be used in conjunction with another handler which
/// reads the parsed `GRPCClientResponsePart<Response>` messages and surfaces them to the caller
/// in some fashion. Note that for unary and client streaming RPCs this handler will only emit at
/// most one response message.
///
/// This handler relies heavily on the `GRPCClientStateMachine` to manage the state of the request
/// and response streams, which share a single HTTP/2 stream for transport.
///
/// Typical usage of this handler is with a `HTTP2StreamMultiplexer` from SwiftNIO HTTP2:
///
/// ```
/// let multiplexer: HTTP2StreamMultiplexer = // ...
/// multiplexer.createStreamChannel(promise: nil) { (channel, streamID) in
///   let clientChannelHandler = GRPCClientChannelHandler<Request, Response>(
///     streamID: streamID,
///     callType: callType,
///     logger: logger
///   )
///   return channel.pipeline.addHandler(clientChannelHandler)
/// }
/// ```
///
/// - Important: This is **NOT** part of the public API. It is declared as
///   `public` because it is used within performance tests.
public final class _GRPCClientChannelHandler {
  private let logger: Logger
  private var stateMachine: GRPCClientStateMachine

  /// Creates a new gRPC channel handler for clients to translate HTTP/2 frames to gRPC messages.
  ///
  /// - Parameters:
  ///   - callType: Type of RPC call being made.
  ///   - logger: Logger.
  public init(callType: GRPCCallType, logger: Logger) {
    self.logger = logger
    switch callType {
    case .unary:
      self.stateMachine = .init(requestArity: .one, responseArity: .one)
    case .clientStreaming:
      self.stateMachine = .init(requestArity: .many, responseArity: .one)
    case .serverStreaming:
      self.stateMachine = .init(requestArity: .one, responseArity: .many)
    case .bidirectionalStreaming:
      self.stateMachine = .init(requestArity: .many, responseArity: .many)
    }
  }
}

// MARK: - GRPCClientChannelHandler: Inbound

extension _GRPCClientChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = HTTP2Frame.FramePayload
  public typealias InboundOut = _RawGRPCClientResponsePart

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let payload = self.unwrapInboundIn(data)
    switch payload {
    case let .headers(content):
      self.readHeaders(content: content, context: context)

    case let .data(content):
      self.readData(content: content, context: context)

    // We don't need to handle other frame type, just drop them instead.
    default:
      // TODO: synthesise a more precise `GRPCStatus` from RST_STREAM frames in accordance
      // with: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#errors
      break
    }
  }

  /// Read the content from an HTTP/2 HEADERS frame received from the server.
  ///
  /// We can receive headers in two cases:
  /// - when the RPC is being acknowledged, and
  /// - when the RPC is being terminated.
  ///
  /// It is also possible for the RPC to be acknowledged and terminated at the same time, the
  /// specification refers to this as a "Trailers-Only" response.
  ///
  /// - Parameter content: Content of the headers frame.
  /// - Parameter context: Channel handler context.
  private func readHeaders(
    content: HTTP2Frame.FramePayload.Headers,
    context: ChannelHandlerContext
  ) {
    self.logger.trace("received HTTP2 frame", metadata: [
      MetadataKey.h2Payload: "HEADERS",
      MetadataKey.h2Headers: "\(content.headers)",
      MetadataKey.h2EndStream: "\(content.endStream)",
    ])

    // In the case of a "Trailers-Only" response there's no guarantee that end-of-stream will be set
    // on the headers frame: end stream may be sent on an empty data frame as well. If the headers
    // contain a gRPC status code then they must be for a "Trailers-Only" response.
    if content.endStream || content.headers.contains(name: GRPCHeaderName.statusCode) {
      // We have the headers, pass them to the next handler:
      context.fireChannelRead(self.wrapInboundOut(.trailingMetadata(content.headers)))

      // Are they valid headers?
      let result = self.stateMachine.receiveEndOfResponseStream(content.headers)
        .mapError { error -> GRPCError.WithContext in
          // The headers aren't valid so let's figure out a reasonable error to forward:
          switch error {
          case let .invalidContentType(contentType):
            return GRPCError.InvalidContentType(contentType).captureContext()
          case let .invalidHTTPStatus(status):
            return GRPCError.InvalidHTTPStatus(status).captureContext()
          case let .invalidHTTPStatusWithGRPCStatus(status):
            return GRPCError.InvalidHTTPStatusWithGRPCStatus(status).captureContext()
          case .invalidState:
            return GRPCError.InvalidState("parsing end-of-stream trailers").captureContext()
          }
        }

      // Okay, what should we tell the next handler?
      switch result {
      case let .success(status):
        context.fireChannelRead(self.wrapInboundOut(.status(status)))
      case let .failure(error):
        context.fireErrorCaught(error)
      }
    } else {
      // "Normal" response headers, but are they valid?
      let result = self.stateMachine.receiveResponseHeaders(content.headers)
        .mapError { error -> GRPCError.WithContext in
          // The headers aren't valid so let's figure out a reasonable error to forward:
          switch error {
          case let .invalidContentType(contentType):
            return GRPCError.InvalidContentType(contentType).captureContext()
          case let .invalidHTTPStatus(status):
            return GRPCError.InvalidHTTPStatus(status).captureContext()
          case .unsupportedMessageEncoding:
            return GRPCError.CompressionUnsupported().captureContext()
          case .invalidState:
            return GRPCError.InvalidState("parsing headers").captureContext()
          }
        }

      // Okay, what should we tell the next handler?
      switch result {
      case .success:
        context.fireChannelRead(self.wrapInboundOut(.initialMetadata(content.headers)))
      case let .failure(error):
        context.fireErrorCaught(error)
      }
    }
  }

  /// Reads the content from an HTTP/2 DATA frame received from the server and buffers the bytes
  /// necessary to deserialize a message (or messages).
  ///
  /// - Parameter content: Content of the data frame.
  /// - Parameter context: Channel handler context.
  private func readData(content: HTTP2Frame.FramePayload.Data, context: ChannelHandlerContext) {
    // Note: this is replicated from NIO's HTTP2ToHTTP1ClientCodec.
    guard case var .byteBuffer(buffer) = content.data else {
      preconditionFailure("Received DATA frame with non-ByteBuffer IOData")
    }

    self.logger.trace("received HTTP2 frame", metadata: [
      MetadataKey.h2Payload: "DATA",
      MetadataKey.h2DataBytes: "\(content.data.readableBytes)",
      MetadataKey.h2EndStream: "\(content.endStream)",
    ])

    // Do we have bytes to read? If there are no bytes to read then we can't do anything. This may
    // happen if the end-of-stream flag is not set on the trailing headers frame (i.e. the one
    // containing the gRPC status code) and an additional empty data frame is sent with the
    // end-of-stream flag set.
    guard buffer.readableBytes > 0 else {
      return
    }

    // Feed the buffer into the state machine.
    let result = self.stateMachine.receiveResponseBuffer(&buffer)
      .mapError { error -> GRPCError.WithContext in
        switch error {
        case .cardinalityViolation:
          return GRPCError.StreamCardinalityViolation.response.captureContext()
        case .deserializationFailed, .leftOverBytes:
          return GRPCError.DeserializationFailure().captureContext()
        case let .decompressionLimitExceeded(compressedSize):
          return GRPCError.DecompressionLimitExceeded(compressedSize: compressedSize)
            .captureContext()
        case .invalidState:
          return GRPCError.InvalidState("parsing data as a response message").captureContext()
        }
      }

    // Did we get any messages?
    switch result {
    case let .success(messages):
      // Awesome: we got some messages. The state machine guarantees we only get at most a single
      // message for unary and client-streaming RPCs.
      for message in messages {
        // Note: `compressed: false` is currently just a placeholder. This is fine since the message
        // context is not currently exposed to the user. If we implement interceptors for the client
        // and decide to surface this information then we'll need to extract that information from
        // the message reader.
        context.fireChannelRead(self.wrapInboundOut(.message(.init(message, compressed: false))))
      }
    case let .failure(error):
      context.fireErrorCaught(error)
    }
  }
}

// MARK: - GRPCClientChannelHandler: Outbound

extension _GRPCClientChannelHandler: ChannelOutboundHandler {
  public typealias OutboundIn = _RawGRPCClientRequestPart
  public typealias OutboundOut = HTTP2Frame.FramePayload

  public func write(context: ChannelHandlerContext, data: NIOAny,
                    promise: EventLoopPromise<Void>?) {
    switch self.unwrapOutboundIn(data) {
    case let .head(requestHead):
      // Feed the request into the state machine:
      switch self.stateMachine.sendRequestHeaders(requestHead: requestHead) {
      case let .success(headers):
        // We're clear to write some headers. Create an appropriate frame and write it.
        let framePayload = HTTP2Frame.FramePayload.headers(.init(headers: headers))
        self.logger.trace("writing HTTP2 frame", metadata: [
          MetadataKey.h2Payload: "HEADERS",
          MetadataKey.h2Headers: "\(headers)",
          MetadataKey.h2EndStream: "false",
        ])
        context.write(self.wrapOutboundOut(framePayload), promise: promise)

      case let .failure(sendRequestHeadersError):
        switch sendRequestHeadersError {
        case .invalidState:
          // This is bad: we need to trigger an error and close the channel.
          promise?.fail(sendRequestHeadersError)
          context.fireErrorCaught(GRPCError.InvalidState("unable to initiate RPC").captureContext())
        }
      }

    case let .message(request):
      // Feed the request message into the state machine:
      let result = self.stateMachine.sendRequest(
        request.message,
        compressed: request.compressed,
        allocator: context.channel.allocator
      )
      switch result {
      case let .success(buffer):
        // We're clear to send a message; wrap it up in an HTTP/2 frame.
        let framePayload = HTTP2Frame.FramePayload.data(.init(data: .byteBuffer(buffer)))
        self.logger.trace("writing HTTP2 frame", metadata: [
          MetadataKey.h2Payload: "DATA",
          MetadataKey.h2DataBytes: "\(buffer.readableBytes)",
          MetadataKey.h2EndStream: "false",
        ])
        context.write(self.wrapOutboundOut(framePayload), promise: promise)

      case let .failure(writeError):
        switch writeError {
        case .cardinalityViolation:
          // This is fine: we can ignore the request. The RPC can continue as if nothing went wrong.
          promise?.fail(writeError)

        case .serializationFailed:
          // This is bad: we need to trigger an error and close the channel.
          promise?.fail(writeError)
          context.fireErrorCaught(GRPCError.SerializationFailure().captureContext())

        case .invalidState:
          promise?.fail(writeError)
          context
            .fireErrorCaught(GRPCError.InvalidState("unable to write message").captureContext())
        }
      }

    case .end:
      // Okay: can we close the request stream?
      switch self.stateMachine.sendEndOfRequestStream() {
      case .success:
        // We can. Send an empty DATA frame with end-stream set.
        let empty = context.channel.allocator.buffer(capacity: 0)
        let framePayload = HTTP2Frame.FramePayload
          .data(.init(data: .byteBuffer(empty), endStream: true))
        self.logger.trace("writing HTTP2 frame", metadata: [
          MetadataKey.h2Payload: "DATA",
          MetadataKey.h2DataBytes: "0",
          MetadataKey.h2EndStream: "true",
        ])
        context.write(self.wrapOutboundOut(framePayload), promise: promise)

      case let .failure(error):
        // Why can't we close the request stream?
        switch error {
        case .alreadyClosed:
          // This is fine: we can just ignore it. The RPC can continue as if nothing went wrong.
          promise?.fail(error)

        case .invalidState:
          // This is bad: we need to trigger an error and close the channel.
          promise?.fail(error)
          context
            .fireErrorCaught(
              GRPCError.InvalidState("unable to close request stream")
                .captureContext()
            )
        }
      }
    }
  }
}
