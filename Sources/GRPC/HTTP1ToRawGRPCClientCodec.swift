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
import Foundation
import NIO
import NIOHTTP1
import Logging

/// Outgoing gRPC package with an unknown message type (represented as the serialized protobuf message).
public enum RawGRPCClientRequestPart {
  case head(HTTPRequestHead)
  case message(Data)
  case end
}

/// Incoming gRPC package with an unknown message type (represented by a byte buffer).
public enum RawGRPCClientResponsePart {
  case headers(HTTPHeaders)
  case message(ByteBuffer)
  case status(GRPCStatus)
}

/// Codec for translating HTTP/1 responses from the server into untyped gRPC packages
/// and vice-versa.
///
/// Most of the inbound processing is done by `LengthPrefixedMessageReader`; which
/// reads length-prefxied gRPC messages into `ByteBuffer`s containing serialized
/// Protobuf messages.
///
/// The outbound processing transforms serialized Protobufs into length-prefixed
/// gRPC messages stored in `ByteBuffer`s.
///
/// See `HTTP1ToRawGRPCServerCodec` for the corresponding server codec.
public final class HTTP1ToRawGRPCClientCodec {
  public init(logger: Logger) {
    self.logger = logger.addingMetadata(
      key: MetadataKey.channelHandler,
      value: "HTTP1ToRawGRPCClientCodec"
    )
    self.messageReader = LengthPrefixedMessageReader(
      mode: .client,
      compressionMechanism: .none,
      logger: logger
    )
  }

  private enum State {
    case expectingHeaders
    case expectingBodyOrTrailers
    case ignore
  }

  private let logger: Logger
  private var state: State = .expectingHeaders {
    didSet {
      self.logger.debug("read state changed from \(oldValue) to \(self.state)")
    }
  }
  private let messageReader: LengthPrefixedMessageReader
  private let messageWriter = LengthPrefixedMessageWriter()
  private var inboundCompression: CompressionMechanism = .none
}

extension HTTP1ToRawGRPCClientCodec: ChannelInboundHandler {
  public typealias InboundIn = HTTPClientResponsePart
  public typealias InboundOut = RawGRPCClientResponsePart

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    if case .ignore = state {
      self.logger.notice("ignoring read data: \(data)")
      return
    }

    do {
      switch self.unwrapInboundIn(data) {
      case .head(let head):
        state = try processHead(context: context, head: head)

      case .body(var message):
        state = try processBody(context: context, messageBuffer: &message)

      case .end(let trailers):
        state = try processTrailers(context: context, trailers: trailers)
      }
    } catch {
      context.fireErrorCaught(error)
      state = .ignore
    }
  }

  /// Forwards the headers from the request head to the next handler.
  ///
  /// - note: Requires the `.expectingHeaders` state.
  private func processHead(context: ChannelHandlerContext, head: HTTPResponseHead) throws -> State {
    self.logger.debug("processing response head: \(head)")
    guard case .expectingHeaders = state else {
      self.logger.error("invalid state '\(state)' while processing response head \(head)")
      throw GRPCError.client(.invalidState("received headers while in state \(state)"))
    }

    // Trailers-Only response.
    if head.headers.contains(name: GRPCHeaderName.statusCode) {
      self.logger.info("found status-code in headers, processing response head as trailers")
      self.state = .expectingBodyOrTrailers
      return try self.processTrailers(context: context, trailers: head.headers)
    }

    // This should be checked *after* the trailers-only response is handled since any status code
    // and message we already have should take precedence over one we generate from the HTTP status
    // code and reason.
    //
    // Source: https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md
    guard head.status == .ok else {
      self.logger.warning("response head did not have 200 OK status: \(head.status)")
      throw GRPCError.client(.HTTPStatusNotOk(head.status))
    }

    let inboundCompression: CompressionMechanism = head.headers[GRPCHeaderName.encoding]
      .first
      .map { CompressionMechanism(rawValue: $0) ?? .unknown } ?? .none

    guard inboundCompression.supported else {
      self.logger.error("remote peer is using unsupported compression: \(inboundCompression)")
      throw GRPCError.client(.unsupportedCompressionMechanism(inboundCompression.rawValue))
    }

    self.logger.info("using inbound compression: \(inboundCompression)")
    self.messageReader.compressionMechanism = inboundCompression

    context.fireChannelRead(self.wrapInboundOut(.headers(head.headers)))
    return .expectingBodyOrTrailers
  }

  /// Processes the given buffer; if a complete message is read then it is forwarded to the
  /// next channel handler.
  ///
  /// - note: Requires the `.expectingBodyOrTrailers` state.
  private func processBody(context: ChannelHandlerContext, messageBuffer: inout ByteBuffer) throws -> State {
    guard case .expectingBodyOrTrailers = state else {
      self.logger.error("invalid state '\(state)' while processing body \(messageBuffer)")
      throw GRPCError.client(.invalidState("received body while in state \(state)"))
    }

    self.messageReader.append(buffer: &messageBuffer)
    while let message = try self.messageReader.nextMessage() {
      context.fireChannelRead(self.wrapInboundOut(.message(message)))
    }

    return .expectingBodyOrTrailers
  }

  /// Forwards a `GRPCStatus` to the next handler. The status and message are extracted
  /// from the trailers if they exist; the `.unknown` status code is used if no status exists.
  private func processTrailers(context: ChannelHandlerContext, trailers: HTTPHeaders?) throws -> State {
    guard case .expectingBodyOrTrailers = state else {
      self.logger.error("invalid state '\(state)' while processing trailers \(String(describing: trailers))")
      throw GRPCError.client(.invalidState("received trailers while in state \(state)"))
    }

    guard let trailers = trailers else {
      self.logger.notice("processing trailers, but no trailers were provided")
      let status = GRPCStatus(code: .unknown, message: nil)
      context.fireChannelRead(self.wrapInboundOut(.status(status)))
      return .ignore
    }

    let status = GRPCStatus(
      code: self.extractStatusCode(from: trailers),
      message: self.extractStatusMessage(from: trailers),
      trailingMetadata: trailers
    )

    context.fireChannelRead(wrapInboundOut(.status(status)))
    return .ignore
  }

  /// Extracts a status code from the given headers, or `.unknown` if one isn't available or the
  /// code is not valid. If multiple values are present, the first is taken.
  private func extractStatusCode(from headers: HTTPHeaders) -> GRPCStatus.Code {
    let statusCodes = headers[GRPCHeaderName.statusCode]

    guard !statusCodes.isEmpty else {
      self.logger.warning("no status-code header")
      return .unknown
    }

    if statusCodes.count > 1 {
      self.logger.notice("multiple values for status-code header: \(statusCodes), using the first")
    }

    // We have at least one value: force unwrapping is fine.
    let statusCode = statusCodes.first!

    if let code = Int(statusCode).flatMap({ GRPCStatus.Code(rawValue: $0) }) {
      return code
    } else {
      self.logger.warning("no known status-code for: \(statusCode)")
      return .unknown
    }
  }

  /// Extracts a status message from the given headers, or `nil` if one isn't available. If
  /// multiple values are present, the first is taken.
  private func extractStatusMessage(from headers: HTTPHeaders) -> String? {
    let statusMessages = headers[GRPCHeaderName.statusMessage]

    guard !statusMessages.isEmpty else {
      self.logger.debug("no status-message header")
      return nil
    }

    if statusMessages.count > 1 {
      self.logger.notice("multiple values for status-message header: \(statusMessages), using the first")
    }

    // We have at least one value: force unwrapping is fine.
    let unmarshalled = statusMessages.first!
    self.logger.debug("unmarshalling status-message: \(unmarshalled)")
    return GRPCStatusMessageMarshaller.unmarshall(unmarshalled)
  }
}

extension HTTP1ToRawGRPCClientCodec: ChannelOutboundHandler {
  public typealias OutboundIn = RawGRPCClientRequestPart
  public typealias OutboundOut = HTTPClientRequestPart

  public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    switch self.unwrapOutboundIn(data) {
    case .head(let requestHead):
      self.logger.debug("writing request head: \(requestHead)")
      context.write(self.wrapOutboundOut(.head(requestHead)), promise: promise)

    case .message(let message):
      var request = context.channel.allocator.buffer(capacity: LengthPrefixedMessageWriter.metadataLength)
      messageWriter.write(message, into: &request, usingCompression: .none)
      self.logger.debug("writing length prefixed protobuf message")
      context.write(self.wrapOutboundOut(.body(.byteBuffer(request))), promise: promise)

    case .end:
      self.logger.debug("writing end")
      context.write(self.wrapOutboundOut(.end(nil)), promise: promise)
    }
  }
}
