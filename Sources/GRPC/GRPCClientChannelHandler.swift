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
import NIO
import NIOHTTP1
import NIOHPACK
import NIOHTTP2
import SwiftProtobuf
import Logging

// TODO: rename GRPCClientRequestPart2 to GRPCClientRequestPart once this is in-place.
/// A gRPC client request message part.
public enum GRPCClientRequestPart2<Request: Message> {
  /// The 'head' of the request, that is, information about the initiation of the RPC.
  case head(GRPCRequestHead)

  /// A deserialized request message to send to the server.
  case request(Request)

  /// Indicates that the client does not intend to send any further messages.
  case end
}

public struct GRPCRequestHead {
  public var scheme: String
  public var path: String
  public var host: String
  public var options: CallOptions
  public var requestID: String

  public init(scheme: String, path: String, host: String, options: CallOptions, requestID: String) {
    self.scheme = scheme
    self.path = path
    self.host = host
    self.options = options
    self.requestID = requestID
  }
}

// TODO: rename GRPCClientResponsePart2 to GRPCClientResponsePart once this is in-place.
/// A gRPC client response message part.
public enum GRPCClientResponsePart2<Response: Message> {
  /// Metadata received as the server acknowledges the RPC.
  case initialMetadata(HPACKHeaders)

  /// A deserialized response message received from the server.
  case response(Response)

  /// The metadata received at the end of the RPC.
  case trailingMetadata(HPACKHeaders)

  /// The final status of the RPC.
  case status(GRPCStatus)
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
}

// MARK: - GRPCClientChannelHandler

/// A channel handler for gRPC clients which translates HTTP/2 frames into gRPC messages.
///
/// This channel handler should typically be used in conjunction with another handler which
/// reads the parsed `GRPCClientResponsePart2<Response>` messages and surfaces them to the caller
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
public final class GRPCClientChannelHandler<Request: Message, Response: Message> {
  let logger: Logger
  let streamID: HTTP2StreamID
  var stateMachine: GRPCClientStateMachine<Request, Response>

  /// Creates a new gRPC channel handler for clients to translate HTTP/2 frames to gRPC messages.
  ///
  /// - Parameters:
  ///   - streamID: The ID of the HTTP/2 stream that this handler will read and write HTTP/2
  ///     frames on.
  ///   - callType: Type of RPC call being made.
  ///   - logger: Logger.
  public init(streamID: HTTP2StreamID, callType: GRPCCallType, logger: Logger) {
    self.streamID = streamID
    self.logger = logger
    switch callType {
    case .unary:
      self.stateMachine = .init(requestArity: .one, responseArity: .one, logger: logger)
    case .clientStreaming:
      self.stateMachine = .init(requestArity: .many, responseArity: .one, logger: logger)
    case .serverStreaming:
      self.stateMachine = .init(requestArity: .one, responseArity: .many, logger: logger)
    case .bidirectionalStreaming:
      self.stateMachine = .init(requestArity: .many, responseArity: .many, logger: logger)
    }
  }
}

// MARK: - GRPCClientChannelHandler: Inbound
extension GRPCClientChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = HTTP2Frame
  public typealias InboundOut = GRPCClientResponsePart2<Response>

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = self.unwrapInboundIn(data)
    switch frame.payload {
    case .headers(let content):
      self.readHeaders(content: content, context: context)

    case .data(let content):
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
  private func readHeaders(content: HTTP2Frame.FramePayload.Headers, context: ChannelHandlerContext) {
    // In the case of a "Trailers-Only" response there's no guarantee that end-of-stream will be set
    // on the headers frame: end stream may be sent on an empty data frame as well. If the headers
    // contain a gRPC status code then they must be for a "Trailers-Only" response.
    if content.endStream || content.headers.contains(name: GRPCHeaderName.statusCode) {
      // We have the headers, pass them to the next handler:
      context.fireChannelRead(self.wrapInboundOut(.trailingMetadata(content.headers)))

      // Are they valid headers?
      let result = self.stateMachine.receiveEndOfResponseStream(content.headers).mapError { error -> GRPCError in
        // The headers aren't valid so let's figure out a reasonable error to forward:
        switch error {
        case .invalidContentType:
          return .client(.invalidContentType)
        case .invalidHTTPStatus(let status):
          return .client(.invalidHTTPStatus(status))
        case .invalidHTTPStatusWithGRPCStatus(let status):
          return .client(.invalidHTTPStatusWithGRPCStatus(status))
        case .invalidState:
          return .client(.invalidState("invalid state parsing headers as trailers-only response"))
        }
      }

      // Okay, what should we tell the next handler?
      switch result {
      case .success(let status):
        context.fireChannelRead(self.wrapInboundOut(.status(status)))
      case .failure(let error):
        context.fireErrorCaught(error)
      }
    } else {
      // "Normal" response headers, but are they valid?
      let result = self.stateMachine.receiveResponseHeaders(content.headers).mapError { error -> GRPCError in
        // The headers aren't valid so let's figure out a reasonable error to forward:
        switch error {
        case .invalidContentType:
          return .client(.invalidContentType)
        case .invalidHTTPStatus(let status):
          return .client(.invalidHTTPStatus(status))
        case .unsupportedMessageEncoding(let encoding):
          return .client(.unsupportedCompressionMechanism(encoding))
        case .invalidState:
          return .client(.invalidState("invalid state parsing headers as trailers-only response"))
        }
      }

      // Okay, what should we tell the next handler?
      switch result {
      case .success:
        context.fireChannelRead(self.wrapInboundOut(.initialMetadata(content.headers)))
      case .failure(let error):
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
    guard case .byteBuffer(var buffer) = content.data else {
      preconditionFailure("Received DATA frame with non-ByteBuffer IOData")
    }

    // Do we have bytes to read? If there are no bytes to read then we can't do anything. This may
    // happen if the end-of-stream flag is not set on the trailing headers frame (i.e. the one
    // containing the gRPC status code) and an additional empty data frame is sent with the
    // end-of-stream flag set.
    guard buffer.readableBytes > 0 else {
      return
    }

    // Feed the buffer into the state machine.
    let result = self.stateMachine.receiveResponseBuffer(&buffer).mapError { error -> GRPCError in
      switch error {
      case .cardinalityViolation:
        return .client(.responseCardinalityViolation)
      case .deserializationFailed, .leftOverBytes:
        return .client(.responseProtoDeserializationFailure)
      case .invalidState:
        return .client(.invalidState("invalid state when parsing data as a response message"))
      }
    }

    // Did we get any messages?
    switch result {
    case .success(let messages):
      // Awesome: we got some messages. The state machine guarantees we only get at most a single
      // message for unary and client-streaming RPCs.
      for message in messages {
        context.fireChannelRead(self.wrapInboundOut(.response(message)))
      }
    case .failure(let error):
      context.fireErrorCaught(error)
    }
  }
}

// MARK: - GRPCClientChannelHandler: Outbound
extension GRPCClientChannelHandler: ChannelOutboundHandler {
  public typealias OutboundIn = GRPCClientRequestPart2<Request>
  public typealias OutboundOut = HTTP2Frame

  public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    switch self.unwrapOutboundIn(data) {
    case .head(let requestHead):
      // Feed the request into the state machine:
      let result = self.stateMachine.sendRequestHeaders(
        scheme: requestHead.scheme,
        host: requestHead.host,
        path: requestHead.path,
        options: requestHead.options,
        requestID: requestHead.requestID
      )

      switch result {
      case .success(let headers):
        // Great, we're clear to write the some headers. Create an appropriate frame and write it.
        let frame = HTTP2Frame(streamID: self.streamID, payload: .headers(.init(headers: headers)))
        context.write(self.wrapOutboundOut(frame), promise: promise)

      case .failure(let sendRequestHeadersError):
        switch sendRequestHeadersError {
        case .invalidState:
          // This is bad: we need to trigger an error and close.
          promise?.fail(sendRequestHeadersError)
          context.fireErrorCaught(GRPCError.client(.invalidState("unable to initiate RPC")))
        }
      }

    case .request(let request):
      // Feed the request message into the state machine:
      let result = self.stateMachine.sendRequest(request, allocator: context.channel.allocator)
      switch result {
      case .success(let buffer):
        // We're clear to send a message; wrap it up in an HTTP/2 frame.
        let frame = HTTP2Frame(
          streamID: self.streamID,
          payload: .data(.init(data: .byteBuffer(buffer)))
        )
        context.write(self.wrapOutboundOut(frame), promise: promise)

      case .failure(let writeError):
        switch writeError {
        case .cardinalityViolation:
          // This is fine: we can ignore the request.
          promise?.fail(writeError)

        case .serializationFailed:
          // This is bad: we need to trigger an error and close.
          promise?.fail(writeError)
          context.fireErrorCaught(GRPCError.client(.requestProtoSerializationFailure))

        case .invalidState:
          promise?.fail(writeError)
          context.fireErrorCaught(GRPCError.client(.invalidState("unable to write message")))
        }
      }

    case .end:
      // Okay: can we close the request stream?
      switch self.stateMachine.sendEndOfRequestStream() {
      case .success(()):
        // We can, great, send an empty DATA frame with end-stream set.
        let empty = context.channel.allocator.buffer(capacity: 0)
        let frame = HTTP2Frame(
          streamID: self.streamID,
          payload: .data(.init(data: .byteBuffer(empty), endStream: true))
        )
        context.write(self.wrapOutboundOut(frame), promise: promise)

      case .failure(let error):
        // We can't close, but why?
        switch error {
        case .alreadyClosed:
          // This is fine: we can just ignore it.
          promise?.fail(error)

        case .invalidState:
          // This is bad: we need to trigger an error and close.
          promise?.fail(error)
          context.fireErrorCaught(GRPCError.client(.invalidState("unable to close request stream")))
        }
      }
    }
  }

  public func triggerUserOutboundEvent(
    context: ChannelHandlerContext,
    event: Any,
    promise: EventLoopPromise<Void>?
  ) {
    if let userEvent = event as? GRPCClientUserEvent {
      switch userEvent {
      case .cancelled:
        context.fireErrorCaught(GRPCClientError.cancelledByClient)
        context.close(mode: .all, promise: promise)
      }
    } else {
      context.triggerUserOutboundEvent(event, promise: promise)
    }
  }
}
