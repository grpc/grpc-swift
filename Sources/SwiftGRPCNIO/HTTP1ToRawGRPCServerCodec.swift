import Foundation
import NIO
import NIOHTTP1
import NIOFoundationCompat

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
  // 1-byte for compression flag, 4-bytes for message length.
  private let protobufMetadataSize = 5

  private var contentType: ContentType?

  // The following buffers use force unwrapping explicitly. With optionals, developers
  // are encouraged to unwrap them using guard-else statements. These don't work cleanly
  // with structs, since the guard-else would create a new copy of the struct, which
  // would then have to be re-assigned into the class variable for the changes to take effect.
  // By force unwrapping, we avoid those reassignments, and the code is a bit cleaner.

  // Buffer to store binary encoded protos as they're being received if the proto is split across
  // multiple buffers.
  private var binaryRequestBuffer: NIO.ByteBuffer!

  // Buffers to store text encoded protos. Only used when content-type is application/grpc-web-text.
  // TODO(kaipi): Extract all gRPC Web processing logic into an independent handler only added on
  // the HTTP1.1 pipeline, as it's starting to get in the way of readability.
  private var requestTextBuffer: NIO.ByteBuffer!
  private var responseTextBuffer: NIO.ByteBuffer!

  var inboundState = InboundState.expectingHeaders
  var outboundState = OutboundState.expectingHeaders
}

extension HTTP1ToRawGRPCServerCodec {
  /// Expected content types for incoming requests.
  private enum ContentType: String {
    /// Binary encoded gRPC request.
    case binary = "application/grpc"
    /// Base64 encoded gRPC-Web request.
    case text = "application/grpc-web-text"
    /// Binary encoded gRPC-Web request.
    case web = "application/grpc-web"
  }

  enum InboundState {
    case expectingHeaders
    case expectingBody(Body)
    // ignore any additional messages; e.g. we've seen .end or we've sent an error and are waiting for the stream to close.
    case ignore

    enum Body {
      case expectingCompressedFlag
      case expectingMessageLength
      case expectingMoreMessageBytes(UInt32)
    }
  }

  enum OutboundState {
    case expectingHeaders
    case expectingBodyOrStatus
    case ignore
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
      throw GRPCServerError.invalidState("expecteded state .expectingHeaders, got \(inboundState)")
    }

    if let contentTypeHeader = requestHead.headers["content-type"].first {
      contentType = ContentType(rawValue: contentTypeHeader)
    } else {
      // If the Content-Type is not present, assume the request is binary encoded gRPC.
      contentType = .binary
    }

    if contentType == .text {
      requestTextBuffer = ctx.channel.allocator.buffer(capacity: 0)
    }

    ctx.fireChannelRead(self.wrapInboundOut(.head(requestHead)))
    return .expectingBody(.expectingCompressedFlag)
  }

  func processBody(ctx: ChannelHandlerContext, body: inout ByteBuffer) throws -> InboundState {
    guard case .expectingBody(let bodyState) = inboundState else {
      throw GRPCServerError.invalidState("expecteded state .expectingBody(_), got \(inboundState)")
    }

    // If the contentType is text, then decode the incoming bytes as base64 encoded, and append
    // it to the binary buffer. If the request is chunked, this section will process the text
    // in the biggest chunk that is multiple of 4, leaving the unread bytes in the textBuffer
    // where it will expect a new incoming chunk.
    if contentType == .text {
      precondition(requestTextBuffer != nil)
      requestTextBuffer.write(buffer: &body)

      // Read in chunks of 4 bytes as base64 encoded strings will always be multiples of 4.
      let readyBytes = requestTextBuffer.readableBytes - (requestTextBuffer.readableBytes % 4)
      guard let base64Encoded = requestTextBuffer.readString(length: readyBytes),
          let decodedData = Data(base64Encoded: base64Encoded) else {
        throw GRPCServerError.base64DecodeError
      }

      body.write(bytes: decodedData)
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
        guard let compressedFlag: Int8 = messageBuffer.readInteger() else { return .expectingCompressedFlag }

        // TODO: Add support for compression.
        guard compressedFlag == 0 else { throw GRPCServerError.unexpectedCompression }

        bodyState = .expectingMessageLength

      case .expectingMessageLength:
        guard let messageLength: UInt32 = messageBuffer.readInteger() else { return .expectingMessageLength }
        bodyState = .expectingMoreMessageBytes(messageLength)

      case .expectingMoreMessageBytes(let bytesOutstanding):
        // We need to account for messages being spread across multiple `ByteBuffer`s so buffer them
        // into `buffer`. Note: when messages are contained within a single `ByteBuffer` we're just
        // taking a slice so don't incur any extra writes.
        guard messageBuffer.readableBytes >= bytesOutstanding else {
          let remainingBytes = bytesOutstanding - numericCast(messageBuffer.readableBytes)

          if self.binaryRequestBuffer != nil {
            self.binaryRequestBuffer.write(buffer: &messageBuffer)
          } else {
            messageBuffer.reserveCapacity(numericCast(bytesOutstanding))
            self.binaryRequestBuffer = messageBuffer
          }
          return .expectingMoreMessageBytes(remainingBytes)
        }

        // We know buffer.readableBytes >= messageLength, so it's okay to force unwrap here.
        var slice = messageBuffer.readSlice(length: numericCast(bytesOutstanding))!

        if self.binaryRequestBuffer != nil {
          self.binaryRequestBuffer.write(buffer: &slice)
          ctx.fireChannelRead(self.wrapInboundOut(.message(self.binaryRequestBuffer)))
        } else {
          ctx.fireChannelRead(self.wrapInboundOut(.message(slice)))
        }

        self.binaryRequestBuffer = nil
        bodyState = .expectingCompressedFlag
      }
    }
  }

  private func processEnd(ctx: ChannelHandlerContext, trailers: HTTPHeaders?) throws -> InboundState {
    if let trailers = trailers {
      throw GRPCServerError.invalidState("unexpected trailers received \(trailers)")
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

    switch self.unwrapOutboundIn(data) {
    case .headers(var headers):
      guard case .expectingHeaders = outboundState else { return }

      var version = HTTPVersion(major: 2, minor: 0)
      if let contentType = contentType {
        headers.add(name: "content-type", value: contentType.rawValue)
        if contentType != .binary {
          version = .init(major: 1, minor: 1)
        }
      }

      if contentType == .text {
        responseTextBuffer = ctx.channel.allocator.buffer(capacity: 0)
      }

      ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: version, status: .ok, headers: headers))), promise: promise)
      outboundState = .expectingBodyOrStatus

    case .message(var messageBytes):
      guard case .expectingBodyOrStatus = outboundState else { return }

      // Write out a length-delimited message payload. See `processBodyState` for the corresponding format.
      var responseBuffer = ctx.channel.allocator.buffer(capacity: messageBytes.readableBytes + protobufMetadataSize)
      responseBuffer.write(integer: Int8(0))  // Compression flag: no compression
      responseBuffer.write(integer: UInt32(messageBytes.readableBytes))
      responseBuffer.write(buffer: &messageBytes)

      if contentType == .text {
        precondition(responseTextBuffer != nil)
        // Store the response into an independent buffer. We can't return the message directly as
        // it needs to be aggregated with all the responses plus the trailers, in order to have
        // the base64 response properly encoded in a single byte stream.
        responseTextBuffer!.write(buffer: &responseBuffer)
        // Since we stored the written data, mark the write promise as successful so that the
        // ServerStreaming provider continues sending the data.
        promise?.succeed(result: Void())
      } else {
        ctx.write(self.wrapOutboundOut(.body(.byteBuffer(responseBuffer))), promise: promise)
      }
      outboundState = .expectingBodyOrStatus

    case .status(let status):
      // If we error before sending the initial headers (e.g. unimplemented method) then we won't have sent the request head.
      // NIOHTTP2 doesn't support sending a single frame as a "Trailers-Only" response so we still need to loop back and
      // send the request head first.
      if case .expectingHeaders = outboundState {
        self.write(ctx: ctx, data: NIOAny(RawGRPCServerResponsePart.headers(HTTPHeaders())), promise: nil)
      }

      var trailers = status.trailingMetadata
      trailers.add(name: "grpc-status", value: String(describing: status.code.rawValue))
      trailers.add(name: "grpc-message", value: status.message)

      if contentType == .text {
        precondition(responseTextBuffer != nil)

        // Encode the trailers into the response byte stream as a length delimited message, as per
        // https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md
        let textTrailers = trailers.map { name, value in "\(name): \(value)" }.joined(separator: "\r\n")
        responseTextBuffer.write(integer: UInt8(0x80))
        responseTextBuffer.write(integer: UInt32(textTrailers.utf8.count))
        responseTextBuffer.write(string: textTrailers)

        // TODO: Binary responses that are non multiples of 3 will end = or == when encoded in
        // base64. Investigate whether this might have any effect on the transport mechanism and
        // client decoding. Initial results say that they are inocuous, but we might have to keep
        // an eye on this in case something trips up.
        if let binaryData = responseTextBuffer.readData(length: responseTextBuffer.readableBytes) {
          let encodedData = binaryData.base64EncodedString()
          responseTextBuffer.clear()
          responseTextBuffer.reserveCapacity(encodedData.utf8.count)
          responseTextBuffer.write(string: encodedData)
        }
        // After collecting all response for gRPC Web connections, send one final aggregated
        // response.
        ctx.write(self.wrapOutboundOut(.body(.byteBuffer(responseTextBuffer))), promise: promise)
        ctx.write(self.wrapOutboundOut(.end(nil)), promise: promise)
      } else {
        ctx.write(self.wrapOutboundOut(.end(trailers)), promise: promise)
      }

      outboundState = .ignore
      inboundState = .ignore
    }
  }
}
