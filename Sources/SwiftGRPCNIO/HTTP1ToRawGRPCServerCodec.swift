import Foundation
import NIO
import NIOHTTP1

/// Incoming gRPC package with an unknown message type (represented by a byte buffer).
public enum RawGRPCServerRequestPart {
  case head(HTTPRequestHead)
  case message(ByteBuffer)
  case end
}

/// Outgoing gRPC package with an unknown message type (represented by `Data`).
public enum RawGRPCServerResponsePart {
  case headers(HTTPHeaders)
  case message(Data)
  case status(GRPCStatus)
}

/// A simple channel handler that translates HTTP1 data types into gRPC packets, and vice versa.
///
/// This codec allows us to use the "raw" gRPC protocol on a low level, with further handlers operationg the protocol
/// on a "higher" level.
///
/// We use HTTP1 (instead of HTTP2) primitives, as these are easier to work with than raw HTTP2
/// primitives while providing all the functionality we need. In addition, this should make implementing gRPC-over-HTTP1
/// (sometimes also called pPRC) easier in the future.
///
/// The translation from HTTP2 to HTTP1 is done by `HTTP2ToHTTP1ServerCodec`.
public final class HTTP1ToRawGRPCServerCodec {
  private enum State {
    case expectingHeaders
    case expectingBody
  }

  private var state = State.expectingHeaders
  private let messageReader = LengthPrefixedMessageReader(mode: .server)
  private let messageWriter = LengthPrefixedMessageWriter()
}

extension HTTP1ToRawGRPCServerCodec: ChannelInboundHandler {
  public typealias InboundIn = HTTPServerRequestPart
  public typealias InboundOut = RawGRPCServerRequestPart
  
  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .head(let requestHead):
      guard case .expectingHeaders = state
        else { preconditionFailure("received headers while in state \(state)") }

      state = .expectingBody
      ctx.fireChannelRead(self.wrapInboundOut(.head(requestHead)))

    case .body(var body):
      guard case .expectingBody = state
        else { preconditionFailure("received body while in state \(state)") }

      do {
        while body.readableBytes > 0 {
          if let message = try messageReader.read(messageBuffer: &body, compression: .none) {
            ctx.fireChannelRead(wrapInboundOut(.message(message)))
          }
        }
      } catch {
        ctx.fireErrorCaught(error)
      }

    case .end(let trailers):
      if let trailers = trailers {
        //! FIXME: Better handle this error.
        print("unexpected trailers received: \(trailers)")
        return
      }
      ctx.fireChannelRead(self.wrapInboundOut(.end))
    }
  }
}

extension HTTP1ToRawGRPCServerCodec: ChannelOutboundHandler {
  public typealias OutboundIn = RawGRPCServerResponsePart
  public typealias OutboundOut = HTTPServerResponsePart
  
  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let responsePart = self.unwrapOutboundIn(data)
    switch responsePart {
    case .headers(let headers):
      //! FIXME: Should return a different version if we want to support pPRC.
      ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok, headers: headers))), promise: promise)

    case .message(let message):
      do {
        let responseBuffer = try messageWriter.write(allocator: ctx.channel.allocator, compression: .none, message: message)
        ctx.write(self.wrapOutboundOut(.body(.byteBuffer(responseBuffer))), promise: promise)
      } catch {
        ctx.fireErrorCaught(error)
      }

    case .status(let status):
      var trailers = status.trailingMetadata
      trailers.add(name: "grpc-status", value: String(describing: status.code.rawValue))
      if let message = status.message {
        trailers.add(name: "grpc-message", value: message)
      }
      ctx.write(self.wrapOutboundOut(.end(trailers)), promise: promise)
    }
  }
}
