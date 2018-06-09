import Foundation
import NIO
import NIOHTTP1

public enum RawGRPCServerRequestPart {
  case headers(HTTPRequestHead)
  case message(ByteBuffer)
  case end
}

public enum RawGRPCServerResponsePart {
  case headers(HTTPHeaders)
  case message(ByteBuffer)
  case status(GRPCStatus)
}

/// A simple channel handler that translates HTTP/1 data types into gRPC packets,
/// and vice versa.
public final class HTTP1ToRawGRPCServerCodec: ChannelInboundHandler, ChannelOutboundHandler {
  public typealias InboundIn = HTTPServerRequestPart
  public typealias InboundOut = RawGRPCServerRequestPart

  public typealias OutboundIn = RawGRPCServerResponsePart
  public typealias OutboundOut = HTTPServerResponsePart

  enum State {
    case expectingHeaders
    case expectingCompressedFlag
    case expectingMessageLength
    case receivedMessageLength(UInt32)

    var expectingBody: Bool {
      switch self {
      case .expectingHeaders: return false
      case .expectingCompressedFlag, .expectingMessageLength, .receivedMessageLength: return true
      }
    }
  }

  private(set) var state = State.expectingHeaders

  private(set) var buffer: NIO.ByteBuffer?

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .head(let headers):
      guard case .expectingHeaders = state
        else { preconditionFailure("received headers while in state \(state)") }

      state = .expectingCompressedFlag
      buffer = ctx.channel.allocator.buffer(capacity: 5)

      ctx.fireChannelRead(self.wrapInboundOut(.headers(headers)))

    case .body(var body):
      guard var buffer = buffer
        else { preconditionFailure("buffer not initialized") }
      assert(state.expectingBody, "received body while in state \(state)")
      buffer.write(buffer: &body)

      requestProcessing: while true {
        switch state {
        case .expectingHeaders: preconditionFailure("unexpected state \(state)")
        case .expectingCompressedFlag:
          guard let compressionFlag: Int8 = buffer.readInteger() else { break requestProcessing }
          precondition(compressionFlag == 0, "unexpected compression flag \(compressionFlag)")
          state = .expectingMessageLength

        case .expectingMessageLength:
          guard let messageLength: UInt32 = buffer.readInteger() else { break requestProcessing }
          state = .receivedMessageLength(messageLength)

        case .receivedMessageLength(let messageLength):
          guard let messageBytes = buffer.readBytes(length: numericCast(messageLength)) else { break }

          var responseBuffer = ctx.channel.allocator.buffer(capacity: messageBytes.count)
          responseBuffer.write(bytes: messageBytes)
          ctx.fireChannelRead(self.wrapInboundOut(.message(responseBuffer)))

          state = .expectingCompressedFlag
        }
      }

    case .end(let trailers):
      assert(trailers == nil, "unexpected trailers received: \(trailers!)")
      ctx.fireChannelRead(self.wrapInboundOut(.end))
    }
  }

  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let responsePart = self.unwrapOutboundIn(data)
    switch responsePart {
    case .headers(let headers):
      //! FIXME: Should return a different version if we want to support pPRC.
      ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok, headers: headers))), promise: promise)
    case .message(var messageBytes):
      var responseBuffer = ctx.channel.allocator.buffer(capacity: messageBytes.readableBytes + 5)
      responseBuffer.write(integer: Int8(0))  // Compression flag: no compression
      responseBuffer.write(integer: UInt32(messageBytes.readableBytes))
      responseBuffer.write(buffer: &messageBytes)
      ctx.write(self.wrapOutboundOut(.body(.byteBuffer(responseBuffer))), promise: promise)
    case .status(let status):
      var trailers = status.trailingMetadata
      trailers.add(name: "grpc-status", value: String(describing: status.code.rawValue))
      trailers.add(name: "grpc-message", value: status.message)
      ctx.write(self.wrapOutboundOut(.end(trailers)), promise: promise)
    }
  }
}
