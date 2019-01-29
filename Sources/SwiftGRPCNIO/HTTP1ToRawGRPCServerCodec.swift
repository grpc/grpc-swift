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
  internal var inboundState = InboundState.expectingHeaders
  internal var outboundState = OutboundState.expectingHeaders

  private var buffer: NIO.ByteBuffer?

  // 1-byte for compression flag, 4-bytes for message length.
  private let protobufMetadataSize = 5
}

extension HTTP1ToRawGRPCServerCodec {
  enum InboundState {
    case expectingHeaders
    case expectingBody(Body)
    // ignore any additional messages; e.g. we've seen .end or we've sent an error and are waiting for the stream to close.
    case ignore

    enum Body {
      case expectingCompressedFlag
      case expectingMessageLength
      case receivedMessageLength(UInt32)
    }
  }

  enum OutboundState {
    case expectingHeaders
    case expectingBodyOrStatus
    case ignore
  }
}

extension HTTP1ToRawGRPCServerCodec {
  struct StateMachineError: Error, GRPCStatusTransformable {
    private let message: String

    init(_ message: String) {
      self.message = message
    }

    func asGRPCStatus() -> GRPCStatus {
      return GRPCStatus.processingError
    }
  }
}

extension HTTP1ToRawGRPCServerCodec: ChannelInboundHandler {
  public typealias InboundIn = HTTPServerRequestPart
  public typealias InboundOut = RawGRPCServerRequestPart

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    if case .ignore = inboundState { return }

    do {
      switch self.unwrapInboundIn(data) {
      case .head(let requestHead):
        inboundState = try processHead(ctx: ctx, requestHead: requestHead)

      case .body(var body):
        inboundState = try processBody(ctx: ctx, body: &body)

      case .end(let trailers):
        inboundState = try processEnd(ctx: ctx, trailers: trailers)
      }
    } catch {
      ctx.fireErrorCaught(error)
      inboundState = .ignore
    }
  }

  func processHead(ctx: ChannelHandlerContext, requestHead: HTTPRequestHead) throws -> InboundState {
    guard case .expectingHeaders = inboundState else {
      throw StateMachineError("expecteded state .expectingHeaders, got \(inboundState)")
    }

    ctx.fireChannelRead(self.wrapInboundOut(.head(requestHead)))

    return .expectingBody(.expectingCompressedFlag)
  }

  func processBody(ctx: ChannelHandlerContext, body: inout ByteBuffer) throws -> InboundState {
    guard case .expectingBody(let bodyState) = inboundState else {
      throw StateMachineError("expecteded state .expectingBody(_), got \(inboundState)")
    }

    return .expectingBody(try processBodyState(ctx: ctx, initialState: bodyState, messageBuffer: &body))
  }

  func processBodyState(ctx: ChannelHandlerContext, initialState: InboundState.Body, messageBuffer: inout ByteBuffer) throws -> InboundState.Body {
    var bodyState = initialState

    // Iterate over all available incoming data, trying to read length-delimited messages.
    // Each message has the following format:
    // - 1 byte "compressed" flag (currently always zero, as we do not support for compression)
    // - 4 byte signed-integer payload length (N)
    // - N bytes payload (normally a valid wire-format protocol buffer)
    while true {
      switch bodyState {
      case .expectingCompressedFlag:
        guard let compressionFlag: Int8 = messageBuffer.readInteger() else { return .expectingCompressedFlag }

        // TODO: Add support for compression.
        guard compressionFlag == 0 else { throw GRPCStatus.unsupportedCompression }

        bodyState = .expectingMessageLength

      case .expectingMessageLength:
        guard let messageLength: UInt32 = messageBuffer.readInteger() else { return .expectingMessageLength }
        bodyState = .receivedMessageLength(messageLength)

      case .receivedMessageLength(let messageLength):
        // We need to account for messages being spread across multiple `ByteBuffer`s so buffer them
        // into `buffer`. Note: when messages are contained within a single `ByteBuffer` we're just
        // taking a slice so don't incur any extra writes.
        guard messageBuffer.readableBytes >= messageLength else {
          let remainingBytes = messageLength - numericCast(messageBuffer.readableBytes)

          if var buffer = buffer {
            buffer.write(buffer: &messageBuffer)
            self.buffer = buffer
          } else {
            messageBuffer.reserveCapacity(numericCast(messageLength))
            self.buffer = messageBuffer
          }

          return .receivedMessageLength(remainingBytes)
        }

        // We know buffer.readableBytes >= messageLength, so it's okay to force unwrap here.
        var slice = messageBuffer.readSlice(length: numericCast(messageLength))!

        if var buffer = buffer {
          buffer.write(buffer: &slice)
          ctx.fireChannelRead(self.wrapInboundOut(.message(buffer)))
        } else {
          ctx.fireChannelRead(self.wrapInboundOut(.message(slice)))
        }

        self.buffer = nil
        bodyState = .expectingCompressedFlag
      }
    }
  }

  private func processEnd(ctx: ChannelHandlerContext, trailers: HTTPHeaders?) throws -> InboundState {
    guard trailers == nil else {
      throw StateMachineError("unexpected trailers received \(String(describing: trailers))")
    }

    ctx.fireChannelRead(self.wrapInboundOut(.end))
    return .ignore
  }
}

extension HTTP1ToRawGRPCServerCodec: ChannelOutboundHandler {
  public typealias OutboundIn = RawGRPCServerResponsePart
  public typealias OutboundOut = HTTPServerResponsePart

  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    if case .ignore = outboundState { return }

    let responsePart = self.unwrapOutboundIn(data)
    switch responsePart {
    case .headers(let headers):
      guard case .expectingHeaders = outboundState else { return }

      //! FIXME: Should return a different version if we want to support pPRC.
      ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok, headers: headers))), promise: promise)
      outboundState = .expectingBodyOrStatus

    case .message(var messageBytes):
      guard case .expectingBodyOrStatus = outboundState else { return }

      // Write out a length-delimited message payload. See `processBodyState` for the corresponding format.
      var responseBuffer = ctx.channel.allocator.buffer(capacity: messageBytes.readableBytes + protobufMetadataSize)
      responseBuffer.write(integer: Int8(0))  // Compression flag: no compression
      responseBuffer.write(integer: UInt32(messageBytes.readableBytes))
      responseBuffer.write(buffer: &messageBytes)
      ctx.write(self.wrapOutboundOut(.body(.byteBuffer(responseBuffer))), promise: promise)
      outboundState = .expectingBodyOrStatus

    case .status(let status):
      var trailers = status.trailingMetadata
      trailers.add(name: "grpc-status", value: String(describing: status.code.rawValue))
      trailers.add(name: "grpc-message", value: status.message)

      // "Trailers-Only" response
      if case .expectingHeaders = outboundState {
        trailers.add(name: "content-type", value: "application/grpc")
        let responseHead = HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok)
        ctx.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
      }

      ctx.writeAndFlush(self.wrapOutboundOut(.end(trailers)), promise: promise)
      outboundState = .ignore
      inboundState = .ignore
    }
  }
}
