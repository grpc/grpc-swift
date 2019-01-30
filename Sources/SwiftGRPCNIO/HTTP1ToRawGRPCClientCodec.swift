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

/// Outgoing gRPC package with an unknown message type (represented as the serialzed protobuf message).
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

/// Codec for translating HTTP/1 resposnes from the server into untyped gRPC packages
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
}

extension HTTP1ToRawGRPCClientCodec: ChannelInboundHandler {
  public typealias InboundIn = HTTPClientResponsePart
  public typealias InboundOut = RawGRPCClientResponsePart

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    if case .ignore = state { return }

    switch unwrapInboundIn(data) {
    case .head(let head):
      state = processHead(ctx: ctx, head: head)

    case .body(var message):
      do {
        state = try processBody(ctx: ctx, messageBuffer: &message)
      } catch {
        ctx.fireErrorCaught(error)
        state = .ignore
      }

    case .end(let trailers):
      state = processTrailers(ctx: ctx, trailers: trailers)
    }
  }

  /// Forwards the headers from the request head to the next handler.
  ///
  /// - note: Requires the `.expectingHeaders` state.
  private func processHead(ctx: ChannelHandlerContext, head: HTTPResponseHead) -> State {
    guard case .expectingHeaders = state
      else { preconditionFailure("received headers while in state \(state)") }

    ctx.fireChannelRead(wrapInboundOut(.headers(head.headers)))
    return .expectingBodyOrTrailers
  }

  /// Processes the given buffer; if a complete message is read then it is forwarded to the
  /// next channel handler.
  ///
  /// - note: Requires the `.expectingBodyOrTrailers` state.
  private func processBody(ctx: ChannelHandlerContext, messageBuffer: inout ByteBuffer) throws -> State {
    guard case .expectingBodyOrTrailers = state
      else { preconditionFailure("received body while in state \(state)") }

    if let message = try self.messageReader.read(messageBuffer: &messageBuffer) {
      ctx.fireChannelRead(wrapInboundOut(.message(message)))
    }

    return .expectingBodyOrTrailers
  }

  /// Forwards a `GRPCStatus` to the next handler. The status and message are extracted
  /// from the trailers if they exist; the `.unknown` status code and an empty message
  /// are used otherwise.
  private func processTrailers(ctx: ChannelHandlerContext, trailers: HTTPHeaders?) -> State {
    guard case .expectingBodyOrTrailers = state
      else { preconditionFailure("received trailers while in state \(state)") }

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
    switch unwrapOutboundIn(data) {
    case .head(let requestHead):
      ctx.write(wrapOutboundOut(.head(requestHead)), promise: promise)

    case .message(let message):
      let request = messageWriter.write(allocator: ctx.channel.allocator, compression: .none, message: message)
      ctx.write(wrapOutboundOut(.body(.byteBuffer(request))), promise: promise)

    case .end:
      ctx.writeAndFlush(wrapOutboundOut(.end(nil)), promise: promise)
    }
  }
}
