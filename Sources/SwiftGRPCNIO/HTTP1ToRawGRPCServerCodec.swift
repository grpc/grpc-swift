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
  /// Expected content types for incoming requests.
  private enum ContentType: String {
    /// Binary encoded gRPC request.
    case binary = "application/grpc"
    /// Base64 encoded gRPC-Web request.
    case text = "application/grpc-web-text"
    /// Binary encoded gRPC-Web request.
    case web = "application/grpc-web"
  }

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

  private var contentType: ContentType?

  // The following buffers use force unwrapping explicitly. With optionals, developers
  // are encouraged to unwrap them using guard-else statements. These don't work cleanly
  // with structs, since the guard-else would create a new copy of the struct, which
  // would then have to be re-assigned into the class variable for the changes to take effect.
  // By force unwrapping, we avoid those reassignments, and the code is a bit cleaner.

  // Buffer to store binary encoded protos as they're being received.
  private var binaryRequestBuffer: NIO.ByteBuffer!

  // Buffers to store text encoded protos. Only used when content-type is application/grpc-web-text.
  // TODO(kaipi): Extract all gRPC Web processing logic into an independent handler only added on
  // the HTTP1.1 pipeline, as it's starting to get in the way of readability.
  private var requestTextBuffer: NIO.ByteBuffer!
  private var responseTextBuffer: NIO.ByteBuffer!
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
      binaryRequestBuffer = ctx.channel.allocator.buffer(capacity: 5)
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

    case .body(var body):
      precondition(binaryRequestBuffer != nil, "buffer not initialized")
      assert(state.expectingBody, "received body while in state \(state)")

      // If the contentType is text, then decode the incoming bytes as base64 encoded, and append
      // it to the binary buffer. If the request is chunked, this section will process the text
      // in the biggest chunk that is multiple of 4, leaving the unread bytes in the textBuffer
      // where it will expect a new incoming chunk.
      if contentType == .text {
        precondition(requestTextBuffer != nil)
        requestTextBuffer.write(buffer: &body)
        // Read in chunks of 4 bytes as base64 encoded strings will always be multiples of 4.
        let readyBytes = requestTextBuffer.readableBytes - (requestTextBuffer.readableBytes % 4)
        guard let base64Encoded = requestTextBuffer.readString(length:readyBytes),
            let decodedData = Data(base64Encoded: base64Encoded) else {
          //! FIXME: Improve error handling when the message couldn't be decoded as base64.
          ctx.close(mode: .all, promise: nil)
          return
        }
        binaryRequestBuffer.write(bytes: decodedData)
      } else {
        binaryRequestBuffer.write(buffer: &body)
      }

      // Iterate over all available incoming data, trying to read length-delimited messages.
      // Each message has the following format:
      // - 1 byte "compressed" flag (currently always zero, as we do not support for compression)
      // - 4 byte signed-integer payload length (N)
      // - N bytes payload (normally a valid wire-format protocol buffer)
      requestProcessing: while true {
        switch state {
        case .expectingHeaders: preconditionFailure("unexpected state \(state)")
        case .expectingCompressedFlag:
          guard let compressionFlag: Int8 = binaryRequestBuffer.readInteger() else { break requestProcessing }
          //! FIXME: Avoid crashing here and instead drop the connection.
          precondition(compressionFlag == 0, "unexpected compression flag \(compressionFlag); compression is not supported and we did not indicate support for it")
          state = .expectingMessageLength

        case .expectingMessageLength:
          guard let messageLength: UInt32 = binaryRequestBuffer.readInteger() else { break requestProcessing }
          state = .receivedMessageLength(messageLength)

        case .receivedMessageLength(let messageLength):
          guard let messageBytes = binaryRequestBuffer.readBytes(length: numericCast(messageLength)) else { break }

          //! FIXME: Use a slice of this buffer instead of copying to a new buffer.
          var messageBuffer = ctx.channel.allocator.buffer(capacity: messageBytes.count)
          messageBuffer.write(bytes: messageBytes)
          ctx.fireChannelRead(self.wrapInboundOut(.message(messageBuffer)))
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
    case .headers:
      var headers = HTTPHeaders()
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
    case .message(var messageBytes):
      // Write out a length-delimited message payload. See `channelRead` fpor the corresponding format.
      var responseBuffer = ctx.channel.allocator.buffer(capacity: messageBytes.readableBytes + 5)
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

    case .status(let status):
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
    }
  }
}
