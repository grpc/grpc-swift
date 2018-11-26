import Foundation
import NIO
import NIOHTTP1

/// Incoming gRPC package with an unknown message type (represented by a byte buffer).
public enum RawGRPCServerRequestPart {
  case head(HTTPRequestHead)
  case message(ByteBuffer)
  case end
}

/// Outgoing gRPC package with an unknown message type (represented by a byte buffer).
public enum RawGRPCServerResponsePart {
  case headers(HTTPHeaders)
  case message(ByteBuffer)
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

  private var state = State.expectingHeaders

  private var buffer: NIO.ByteBuffer?
}

extension HTTP1ToRawGRPCServerCodec: ChannelInboundHandler {
  public typealias InboundIn = HTTPServerRequestPart
  public typealias InboundOut = RawGRPCServerRequestPart
  
  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .head(let requestHead):
      guard case .expectingHeaders = state
        else { preconditionFailure("received headers while in state \(state)") }

      state = .expectingCompressedFlag
      buffer = ctx.channel.allocator.buffer(capacity: 5)

      ctx.fireChannelRead(self.wrapInboundOut(.head(requestHead)))

    case .body(var body):
      guard var buffer = buffer
        else { preconditionFailure("buffer not initialized") }
      assert(state.expectingBody, "received body while in state \(state)")
      buffer.write(buffer: &body)

      // Iterate over all available incoming data, trying to read length-delimited messages.
      // Each message has the following format:
      // - 1 byte "compressed" flag (currently always zero, as we do not support for compression)
      // - 4 byte signed-integer payload length (N)
      // - N bytes payload (normally a valid wire-format protocol buffer)
      requestProcessing: while true {
        switch state {
        case .expectingHeaders: preconditionFailure("unexpected state \(state)")
        case .expectingCompressedFlag:
          guard let compressionFlag: Int8 = buffer.readInteger() else { break requestProcessing }
          //! FIXME: Avoid crashing here and instead drop the connection.
          precondition(compressionFlag == 0, "unexpected compression flag \(compressionFlag); compression is not supported and we did not indicate support for it")
          state = .expectingMessageLength

        case .expectingMessageLength:
          guard let messageLength: UInt32 = buffer.readInteger() else { break requestProcessing }
          state = .receivedMessageLength(messageLength)

        case .receivedMessageLength(let messageLength):
          guard let messageBytes = buffer.readBytes(length: numericCast(messageLength)) else { break }

          //! FIXME: Use a slice of this buffer instead of copying to a new buffer.
          var responseBuffer = ctx.channel.allocator.buffer(capacity: messageBytes.count)
          responseBuffer.write(bytes: messageBytes)
          ctx.fireChannelRead(self.wrapInboundOut(.message(responseBuffer)))
          //! FIXME: Call buffer.discardReadBytes() here?
          //! ALTERNATIVE: Check if the buffer has no further data right now, then clear it.

          state = .expectingCompressedFlag
        }
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
    case .message(var messageBytes):
      // Write out a length-delimited message payload. See `channelRead` fpor the corresponding format.
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
