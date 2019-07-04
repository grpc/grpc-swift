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
import NIOFoundationCompat

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
  public init() {}

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

  var messageWriter = LengthPrefixedMessageWriter()
  var messageReader = LengthPrefixedMessageReader(mode: .server, compressionMechanism: .none)
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
    case expectingBody
    // ignore any additional messages; e.g. we've seen .end or we've sent an error and are waiting for the stream to close.
    case ignore
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

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    if case .ignore = inboundState { return }

    do {
      switch self.unwrapInboundIn(data) {
      case .head(let requestHead):
        inboundState = try processHead(context: context, requestHead: requestHead)

      case .body(var body):
        inboundState = try processBody(context: context, body: &body)

      case .end(let trailers):
        inboundState = try processEnd(context: context, trailers: trailers)
      }
    } catch {
      context.fireErrorCaught(error)
      inboundState = .ignore
    }
  }

  func processHead(context: ChannelHandlerContext, requestHead: HTTPRequestHead) throws -> InboundState {
    guard case .expectingHeaders = inboundState else {
      throw GRPCError.server(.invalidState("expecteded state .expectingHeaders, got \(inboundState)"))
    }

    if let contentTypeHeader = requestHead.headers["content-type"].first {
      contentType = ContentType(rawValue: contentTypeHeader)
    } else {
      // If the Content-Type is not present, assume the request is binary encoded gRPC.
      contentType = .binary
    }

    if contentType == .text {
      requestTextBuffer = context.channel.allocator.buffer(capacity: 0)
    }

    context.fireChannelRead(self.wrapInboundOut(.head(requestHead)))
    return .expectingBody
  }

  func processBody(context: ChannelHandlerContext, body: inout ByteBuffer) throws -> InboundState {
    guard case .expectingBody = inboundState else {
      throw GRPCError.server(.invalidState("expecteded state .expectingBody, got \(inboundState)"))
    }

    // If the contentType is text, then decode the incoming bytes as base64 encoded, and append
    // it to the binary buffer. If the request is chunked, this section will process the text
    // in the biggest chunk that is multiple of 4, leaving the unread bytes in the textBuffer
    // where it will expect a new incoming chunk.
    if contentType == .text {
      precondition(requestTextBuffer != nil)
      requestTextBuffer.writeBuffer(&body)

      // Read in chunks of 4 bytes as base64 encoded strings will always be multiples of 4.
      let readyBytes = requestTextBuffer.readableBytes - (requestTextBuffer.readableBytes % 4)
      guard let base64Encoded = requestTextBuffer.readString(length: readyBytes),
          let decodedData = Data(base64Encoded: base64Encoded) else {
        throw GRPCError.server(.base64DecodeError)
      }

      body.writeBytes(decodedData)
    }

    self.messageReader.append(buffer: &body)
    while let message = try self.messageReader.nextMessage() {
      context.fireChannelRead(self.wrapInboundOut(.message(message)))
    }

    return .expectingBody
  }

  private func processEnd(context: ChannelHandlerContext, trailers: HTTPHeaders?) throws -> InboundState {
    if let trailers = trailers {
      throw GRPCError.server(.invalidState("unexpected trailers received \(trailers)"))
    }

    context.fireChannelRead(self.wrapInboundOut(.end))
    return .ignore
  }
}

extension HTTP1ToRawGRPCServerCodec: ChannelOutboundHandler {
  public typealias OutboundIn = RawGRPCServerResponsePart
  public typealias OutboundOut = HTTPServerResponsePart

  public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
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
        responseTextBuffer = context.channel.allocator.buffer(capacity: 0)
      }

      context.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: version, status: .ok, headers: headers))), promise: promise)
      outboundState = .expectingBodyOrStatus

    case .message(let messageBytes):
      guard case .expectingBodyOrStatus = outboundState else { return }

      if contentType == .text {
        precondition(self.responseTextBuffer != nil)

        // Store the response into an independent buffer. We can't return the message directly as
        // it needs to be aggregated with all the responses plus the trailers, in order to have
        // the base64 response properly encoded in a single byte stream.
        messageWriter.write(messageBytes, into: &self.responseTextBuffer, usingCompression: .none)

        // Since we stored the written data, mark the write promise as successful so that the
        // ServerStreaming provider continues sending the data.
        promise?.succeed(())
      } else {
        var responseBuffer = context.channel.allocator.buffer(capacity: LengthPrefixedMessageWriter.metadataLength)
        messageWriter.write(messageBytes, into: &responseBuffer, usingCompression: .none)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(responseBuffer))), promise: promise)
      }
      outboundState = .expectingBodyOrStatus

    case .status(let status):
      // If we error before sending the initial headers (e.g. unimplemented method) then we won't have sent the request head.
      // NIOHTTP2 doesn't support sending a single frame as a "Trailers-Only" response so we still need to loop back and
      // send the request head first.
      if case .expectingHeaders = outboundState {
        self.write(context: context, data: NIOAny(RawGRPCServerResponsePart.headers(HTTPHeaders())), promise: nil)
      }

      var trailers = status.trailingMetadata
      trailers.add(name: GRPCHeaderName.statusCode, value: String(describing: status.code.rawValue))
      if let message = status.message.flatMap(GRPCStatusMessageMarshaller.marshall) {
        trailers.add(name: GRPCHeaderName.statusMessage, value: message)
      }

      if contentType == .text {
        precondition(responseTextBuffer != nil)

        // Encode the trailers into the response byte stream as a length delimited message, as per
        // https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md
        let textTrailers = trailers.map { name, value in "\(name): \(value)" }.joined(separator: "\r\n")
        responseTextBuffer.writeInteger(UInt8(0x80))
        responseTextBuffer.writeInteger(UInt32(textTrailers.utf8.count))
        responseTextBuffer.writeString(textTrailers)

        // TODO: Binary responses that are non multiples of 3 will end = or == when encoded in
        // base64. Investigate whether this might have any effect on the transport mechanism and
        // client decoding. Initial results say that they are inocuous, but we might have to keep
        // an eye on this in case something trips up.
        if let binaryData = responseTextBuffer.readData(length: responseTextBuffer.readableBytes) {
          let encodedData = binaryData.base64EncodedString()
          responseTextBuffer.clear()
          responseTextBuffer.reserveCapacity(encodedData.utf8.count)
          responseTextBuffer.writeString(encodedData)
        }
        // After collecting all response for gRPC Web connections, send one final aggregated
        // response.
        context.write(self.wrapOutboundOut(.body(.byteBuffer(responseTextBuffer))), promise: promise)
        context.write(self.wrapOutboundOut(.end(nil)), promise: promise)
      } else {
        context.write(self.wrapOutboundOut(.end(trailers)), promise: promise)
      }

      outboundState = .ignore
      inboundState = .ignore
    }
  }
}
