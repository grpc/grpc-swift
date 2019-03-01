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
  public init() {}

  private enum State {
    case expectingHeaders
    case expectingBodyOrTrailers
    case ignore
  }

  private var state: State = .expectingHeaders
  private let messageReader = LengthPrefixedMessageReader(mode: .client)
  private let messageWriter = LengthPrefixedMessageWriter()
  private var inboundCompression: CompressionMechanism = .none
}

extension HTTP1ToRawGRPCClientCodec: ChannelInboundHandler {
  public typealias InboundIn = HTTPClientResponsePart
  public typealias InboundOut = RawGRPCClientResponsePart

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    if case .ignore = state { return }

    do {
      switch self.unwrapInboundIn(data) {
      case .head(let head):
        state = try processHead(ctx: ctx, head: head)

      case .body(var message):
        state = try processBody(ctx: ctx, messageBuffer: &message)

      case .end(let trailers):
        state = try processTrailers(ctx: ctx, trailers: trailers)
      }
    } catch {
      ctx.fireErrorCaught(error)
      state = .ignore
    }
  }

  /// Forwards the headers from the request head to the next handler.
  ///
  /// - note: Requires the `.expectingHeaders` state.
  private func processHead(ctx: ChannelHandlerContext, head: HTTPResponseHead) throws -> State {
    guard case .expectingHeaders = state else {
      throw GRPCError.client(.invalidState("received headers while in state \(state)"))
    }

    guard head.status == .ok else {
      throw GRPCError.client(.HTTPStatusNotOk(head.status))
    }

    if let encodingType = head.headers["grpc-encoding"].first {
      self.inboundCompression = CompressionMechanism(rawValue: encodingType) ?? .unknown
    }

    guard inboundCompression.supported else {
      throw GRPCError.client(.unsupportedCompressionMechanism(inboundCompression.rawValue))
    }

    ctx.fireChannelRead(self.wrapInboundOut(.headers(head.headers)))
    return .expectingBodyOrTrailers
  }

  /// Processes the given buffer; if a complete message is read then it is forwarded to the
  /// next channel handler.
  ///
  /// - note: Requires the `.expectingBodyOrTrailers` state.
  private func processBody(ctx: ChannelHandlerContext, messageBuffer: inout ByteBuffer) throws -> State {
    guard case .expectingBodyOrTrailers = state else {
      throw GRPCError.client(.invalidState("received body while in state \(state)"))
    }

    for message in try self.messageReader.consume(messageBuffer: &messageBuffer, compression: inboundCompression) {
      ctx.fireChannelRead(self.wrapInboundOut(.message(message)))
    }

    return .expectingBodyOrTrailers
  }

  /// Forwards a `GRPCStatus` to the next handler. The status and message are extracted
  /// from the trailers if they exist; the `.unknown` status code is used if no status exists.
  private func processTrailers(ctx: ChannelHandlerContext, trailers: HTTPHeaders?) throws -> State {
    guard case .expectingBodyOrTrailers = state else {
      throw GRPCError.client(.invalidState("received trailers while in state \(state)"))
    }

    let statusCode = trailers?["grpc-status"].first
      .flatMap { Int($0) }
      .flatMap { StatusCode(rawValue: $0) }
    let statusMessage = trailers?["grpc-message"].first

    ctx.fireChannelRead(wrapInboundOut(.status(GRPCStatus(code: statusCode ?? .unknown, message: statusMessage))))
    return .ignore
  }
}

extension HTTP1ToRawGRPCClientCodec: ChannelOutboundHandler {
  public typealias OutboundIn = RawGRPCClientRequestPart
  public typealias OutboundOut = HTTPClientRequestPart

  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    switch self.unwrapOutboundIn(data) {
    case .head(let requestHead):
      ctx.write(self.wrapOutboundOut(.head(requestHead)), promise: promise)

    case .message(let message):
      var request = ctx.channel.allocator.buffer(capacity: LengthPrefixedMessageWriter.metadataLength)
      messageWriter.write(message, into: &request, usingCompression: .none)
      ctx.write(self.wrapOutboundOut(.body(.byteBuffer(request))), promise: promise)

    case .end:
      ctx.write(self.wrapOutboundOut(.end(nil)), promise: promise)
    }
  }
}
