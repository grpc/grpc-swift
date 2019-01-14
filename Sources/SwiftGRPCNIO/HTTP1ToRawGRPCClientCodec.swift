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

/// Outgoing gRPC package with an unknown message type (represented by a byte buffer).
public enum RawGRPCClientRequestPart {
  case head(HTTPRequestHead)
  case message(ByteBuffer)
  case end
}

/// Incoming gRPC package with an unknown message type (represented by a byte buffer).
public enum RawGRPCClientResponsePart {
  case headers(HTTPHeaders)
  case message(ByteBuffer)
  case status(GRPCStatus)
}

public final class HTTP1ToRawGRPCClientCodec {
  private enum State {
    case expectingHeaders
    case expectingBodyOrTrailers
    case expectingCompressedFlag
    case expectingMessageLength
    case receivedMessageLength(UInt32)

    var expectingBody: Bool {
      switch self {
      case .expectingHeaders: return false
      case .expectingBodyOrTrailers, .expectingCompressedFlag, .expectingMessageLength, .receivedMessageLength: return true
      }
    }
  }

  public init() {
  }

  private var state: State = .expectingHeaders
  private var buffer: NIO.ByteBuffer?
}

extension HTTP1ToRawGRPCClientCodec: ChannelInboundHandler {
  public typealias InboundIn = HTTPClientResponsePart
  public typealias InboundOut = RawGRPCClientResponsePart

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch unwrapInboundIn(data) {
    case .head(let head):
      guard case .expectingHeaders = state
        else { preconditionFailure("received headers while in state \(state)") }

      state = .expectingBodyOrTrailers
      ctx.fireChannelRead(wrapInboundOut(.headers(head.headers)))

    case .body(var message):
      if case .expectingBodyOrTrailers = state {
        state = .expectingCompressedFlag
        if buffer == nil {
          buffer = ctx.channel.allocator.buffer(capacity: 5)
        }
      }

      precondition(state.expectingBody, "received body while in state \(state)")

      guard var buffer = buffer else {
        preconditionFailure("buffer is not initialized")
      }

      buffer.write(buffer: &message)

      requestProcessing: while true {
        switch state {
        case .expectingHeaders, .expectingBodyOrTrailers:
          preconditionFailure("unexpected state '\(state)'")

        case .expectingCompressedFlag:
          guard let compressionFlag: Int8 = buffer.readInteger() else { break requestProcessing }
          precondition(compressionFlag == 0, "unexpected compression flag \(compressionFlag); compression is not supported and we did not indicate support for it")
          state = .expectingMessageLength

        case .expectingMessageLength:
          guard let messageLength: UInt32 = buffer.readInteger() else { break requestProcessing }
          state = .receivedMessageLength(messageLength)

        case .receivedMessageLength(let messageLength):
          guard let responseBuffer = buffer.readSlice(length: numericCast(messageLength)) else { break }
          ctx.fireChannelRead(self.wrapInboundOut(.message(responseBuffer)))

          state = .expectingBodyOrTrailers
          break requestProcessing
        }
      }

    case .end(let headers):
      guard case .expectingBodyOrTrailers = state
        else { preconditionFailure("received trailers while in state \(state)") }

      let statusCode = parseGRPCStatus(from: headers?["grpc-status"].first)
      let statusMessage = headers?["grpc-message"].first

      ctx.fireChannelRead(wrapInboundOut(.status(GRPCStatus(code: statusCode, message: statusMessage))))
      state = .expectingHeaders

    }
  }

  private func parseGRPCStatus(from status: String?) -> StatusCode {
    guard let status = status,
      let statusInt = Int(status),
      let statusCode = StatusCode(rawValue: statusInt)
      else { return .unknown }

    return statusCode
  }
}


extension HTTP1ToRawGRPCClientCodec: ChannelOutboundHandler {
  public typealias OutboundIn = RawGRPCClientRequestPart
  public typealias OutboundOut = HTTPClientRequestPart

  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    switch unwrapOutboundIn(data) {
    case .head(let requestHead):
      ctx.write(wrapOutboundOut(.head(requestHead)), promise: promise)

    case .message(var messageBytes):
      var requestBuffer = ctx.channel.allocator.buffer(capacity: messageBytes.readableBytes + 5)
      requestBuffer.write(integer: Int8(0))
      requestBuffer.write(integer: UInt32(messageBytes.readableBytes))
      requestBuffer.write(buffer: &messageBytes)
      ctx.write(wrapOutboundOut(.body(.byteBuffer(requestBuffer))), promise: promise)

    case .end:
      ctx.writeAndFlush(wrapOutboundOut(.end(nil)), promise: promise)
    }

  }
}
