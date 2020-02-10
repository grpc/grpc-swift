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
import Logging

/// Incoming gRPC package with a fixed message type.
///
/// - Important: This is **NOT** part of the public API.
public enum _GRPCServerRequestPart<RequestPayload: GRPCPayload> {
  case head(HTTPRequestHead)
  case message(RequestPayload)
  case end
}

/// Outgoing gRPC package with a fixed message type.
///
/// - Important: This is **NOT** part of the public API.
public enum _GRPCServerResponsePart<ResponsePayload: GRPCPayload> {
  case headers(HTTPHeaders)
  case message(_MessageContext<ResponsePayload>)
  case statusAndTrailers(GRPCStatus, HTTPHeaders)
}

/// A simple channel handler that translates HTTP1 data types into gRPC packets, and vice versa.
///
/// We use HTTP1 (instead of HTTP2) primitives, as these are easier to work with than raw HTTP2
/// primitives while providing all the functionality we need. In addition, it allows us to support
/// gRPC-Web (gRPC over HTTP1).
///
/// The translation from HTTP2 to HTTP1 is done by `HTTP2ToHTTP1ServerCodec`.
public final class HTTP1ToGRPCServerCodec<Request: GRPCPayload, Response: GRPCPayload> {
  public init(encoding: Server.Configuration.MessageEncoding, logger: Logger) {
    self.encoding = encoding
    self.logger = logger

    var accessLog = Logger(subsystem: .serverAccess)
    accessLog[metadataKey: MetadataKey.requestID] = logger[metadataKey: MetadataKey.requestID]
    self.accessLog = accessLog
    self.messageReader = LengthPrefixedMessageReader()
    self.messageWriter = LengthPrefixedMessageWriter()
  }

  private var contentType: ContentType?

  private let encoding: Server.Configuration.MessageEncoding
  private var acceptEncodingHeader: String? = nil
  private var responseEncodingHeader: String? = nil

  private let logger: Logger
  private let accessLog: Logger
  private var stopwatch: Stopwatch?

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

  var inboundState = InboundState.expectingHeaders {
    willSet {
      guard newValue != self.inboundState else { return }
      self.logger.debug("inbound state changed", metadata: ["old_state": "\(self.inboundState)", "new_state": "\(newValue)"])
    }
  }
  var outboundState = OutboundState.expectingHeaders {
    willSet {
      guard newValue != self.outboundState else { return }
      self.logger.debug("outbound state changed", metadata: ["old_state": "\(self.outboundState)", "new_state": "\(newValue)"])
    }
  }

  var messageReader: LengthPrefixedMessageReader
  var messageWriter: LengthPrefixedMessageWriter
}

extension HTTP1ToGRPCServerCodec {
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

extension HTTP1ToGRPCServerCodec: ChannelInboundHandler {
  public typealias InboundIn = HTTPServerRequestPart
  public typealias InboundOut = _GRPCServerRequestPart<Request>

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    if case .ignore = inboundState {
      self.logger.notice("ignoring read data", metadata: ["data": "\(data)"])
      return
    }

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
    self.logger.debug("processing request head", metadata: ["head": "\(requestHead)"])
    guard case .expectingHeaders = inboundState else {
      self.logger.error("invalid state while processing request head",
                        metadata: ["state": "\(inboundState)", "head": "\(requestHead)"])
      throw GRPCError.InvalidState("expected state .expectingHeaders, got \(inboundState)").captureContext()
    }

    self.stopwatch = .start()
    self.accessLog.debug("rpc call started", metadata: [
      "path": "\(requestHead.uri)",
      "method": "\(requestHead.method)",
      "version": "\(requestHead.version)"
    ])

    if let contentType = requestHead.headers.first(name: GRPCHeaderName.contentType).flatMap(ContentType.init) {
      self.contentType = contentType
    } else {
      self.logger.debug("no 'content-type' header, assuming content type is 'application/grpc'")
      // If the Content-Type is not present, assume the request is binary encoded gRPC.
      self.contentType = .protobuf
    }

    if self.contentType == .webTextProtobuf {
      requestTextBuffer = context.channel.allocator.buffer(capacity: 0)
    }

    // What compression was used for sending requests?
    if let encodingHeader = requestHead.headers.first(name: GRPCHeaderName.encoding) {
      switch self.validate(requestEncoding: encodingHeader) {
      case .unsupported:
        // We don't support this encoding, we must let the client know what we do support.
        self.acceptEncodingHeader = self.makeAcceptEncodingHeader()

        let message: String
        let headers: HTTPHeaders
        if let advertised = self.acceptEncodingHeader {
          message = "'\(encodingHeader)' compression is not supported, supported: \(advertised)"
          headers = [GRPCHeaderName.acceptEncoding: advertised]
        } else {
          message = "'\(encodingHeader)' compression is not supported"
          headers = .init()
        }

        let status = GRPCStatus(code: .unimplemented, message: message)
        defer {
          self.write(context: context, data: NIOAny(OutboundIn.statusAndTrailers(status, headers)), promise: nil)
          self.flush(context: context)
        }
        // We're about to fast-fail, so ignore any following inbound messages.
        return .ignore

      case .supported(let algorithm):
        self.messageReader = LengthPrefixedMessageReader(compression: algorithm)

      case .supportedButNotDisclosed(let algorithm):
        self.messageReader = LengthPrefixedMessageReader(compression: algorithm)
        // From: https://github.com/grpc/grpc/blob/master/doc/compression.md
        //
        //   Note that a peer MAY choose to not disclose all the encodings it supports. However, if
        //   it receives a message compressed in an undisclosed but supported encoding, it MUST
        //   include said encoding in the response's grpc-accept-encoding header.
        self.acceptEncodingHeader = self.makeAcceptEncodingHeader(includeExtra: algorithm)
      }
    } else {
      self.messageReader = LengthPrefixedMessageReader(compression: .none)
      self.acceptEncodingHeader = nil
    }

    // What compression should we use for writing responses?
    let clientAcceptableEncoding = requestHead.headers[canonicalForm: GRPCHeaderName.acceptEncoding]
    if let responseEncoding = self.selectResponseEncoding(from: clientAcceptableEncoding) {
      self.messageWriter = LengthPrefixedMessageWriter(compression: responseEncoding)
      self.responseEncodingHeader = responseEncoding.name
    } else {
      self.messageWriter = LengthPrefixedMessageWriter(compression: .none)
      self.responseEncodingHeader = nil
    }

    context.fireChannelRead(self.wrapInboundOut(.head(requestHead)))
    return .expectingBody
  }

  func processBody(context: ChannelHandlerContext, body: inout ByteBuffer) throws -> InboundState {
    self.logger.debug("processing body: \(body)")
    guard case .expectingBody = inboundState else {
      self.logger.error("invalid state while processing body",
                        metadata: ["state": "\(inboundState)", "body": "\(body)"])
      throw GRPCError.InvalidState("expected state .expectingBody, got \(inboundState)").captureContext()
    }

    // If the contentType is text, then decode the incoming bytes as base64 encoded, and append
    // it to the binary buffer. If the request is chunked, this section will process the text
    // in the biggest chunk that is multiple of 4, leaving the unread bytes in the textBuffer
    // where it will expect a new incoming chunk.
    if self.contentType == .webTextProtobuf {
      precondition(requestTextBuffer != nil)
      requestTextBuffer.writeBuffer(&body)

      // Read in chunks of 4 bytes as base64 encoded strings will always be multiples of 4.
      let readyBytes = requestTextBuffer.readableBytes - (requestTextBuffer.readableBytes % 4)
      guard let base64Encoded = requestTextBuffer.readString(length: readyBytes),
          let decodedData = Data(base64Encoded: base64Encoded) else {
          throw GRPCError.Base64DecodeError().captureContext()
      }

      body.writeBytes(decodedData)
    }

    self.messageReader.append(buffer: &body)
    var requests: [Request] = []
    do {
      while var buffer = try self.messageReader.nextMessage() {
        requests.append(try Request(serializedByteBuffer: &buffer))
      }
    } catch {
      context.fireErrorCaught(GRPCError.DeserializationFailure().captureContext())
      return .ignore
    }

    requests.forEach {
      context.fireChannelRead(self.wrapInboundOut(.message($0)))
    }

    return .expectingBody
  }

  private func processEnd(context: ChannelHandlerContext, trailers: HTTPHeaders?) throws -> InboundState {
    self.logger.debug("processing end")
    if let trailers = trailers {
      self.logger.error("unexpected trailers when processing stream end", metadata: ["trailers": "\(trailers)"])
      throw GRPCError.InvalidState("unexpected trailers received").captureContext()
    }

    context.fireChannelRead(self.wrapInboundOut(.end))
    return .ignore
  }
}

extension HTTP1ToGRPCServerCodec: ChannelOutboundHandler {
  public typealias OutboundIn = _GRPCServerResponsePart<Response>
  public typealias OutboundOut = HTTPServerResponsePart

  public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    if case .ignore = self.outboundState {
      self.logger.notice("ignoring written data: \(data)")
      promise?.fail(GRPCError.InvalidState("rpc has already finished").captureContext())
      return
    }

    switch self.unwrapOutboundIn(data) {
    case .headers(var headers):
      guard case .expectingHeaders = self.outboundState else {
        self.logger.error("invalid state while writing headers",
                          metadata: ["state": "\(self.outboundState)", "headers": "\(headers)"])
        return
      }

      var version = HTTPVersion(major: 2, minor: 0)
      if let contentType = self.contentType {
        headers.add(name: GRPCHeaderName.contentType, value: contentType.canonicalValue)
        if contentType != .protobuf {
          version = .init(major: 1, minor: 1)
        }
      }

      if self.contentType == .webTextProtobuf {
        responseTextBuffer = context.channel.allocator.buffer(capacity: 0)
      }

      // Are we compressing responses?
      if let responseEncoding = self.responseEncodingHeader {
        headers.add(name: GRPCHeaderName.encoding, value: responseEncoding)
      }

      // The client may have sent us a message using an encoding we didn't advertise; we'll send
      // an accept-encoding header back if that's the case.
      if let acceptEncoding = self.acceptEncodingHeader {
        headers.add(name: GRPCHeaderName.acceptEncoding, value: acceptEncoding)
      }

      context.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: version, status: .ok, headers: headers))), promise: promise)
      self.outboundState = .expectingBodyOrStatus

    case .message(let messageContext):
      guard case .expectingBodyOrStatus = self.outboundState else {
        self.logger.error("invalid state while writing message", metadata: ["state": "\(self.outboundState)"])
        return
      }

      do {
        if contentType == .webTextProtobuf {
          // Store the response into an independent buffer. We can't return the message directly as
          // it needs to be aggregated with all the responses plus the trailers, in order to have
          // the base64 response properly encoded in a single byte stream.
          precondition(self.responseTextBuffer != nil)
          try self.messageWriter.write(
            messageContext.message,
            into: &self.responseTextBuffer,
            compressed: messageContext.compressed
          )

          // Since we stored the written data, mark the write promise as successful so that the
          // ServerStreaming provider continues sending the data.
          promise?.succeed(())
        } else {
          var lengthPrefixedMessageBuffer = context.channel.allocator.buffer(capacity: 0)
          try self.messageWriter.write(
            messageContext.message,
            into: &lengthPrefixedMessageBuffer,
            compressed: messageContext.compressed
          )
          context.write(self.wrapOutboundOut(.body(.byteBuffer(lengthPrefixedMessageBuffer))), promise: promise)
        }
      } catch {
        let error = GRPCError.SerializationFailure().captureContext()
        promise?.fail(error)
        context.fireErrorCaught(error)
        self.outboundState = .ignore
        return
      }

      self.outboundState = .expectingBodyOrStatus

    case let .statusAndTrailers(status, trailers):
      // If we error before sending the initial headers then we won't have sent the request head.
      // NIOHTTP2 doesn't support sending a single frame as a "Trailers-Only" response so we still
      // need to loop back and send the request head first.
      if case .expectingHeaders = self.outboundState {
        self.write(context: context, data: NIOAny(OutboundIn.headers(HTTPHeaders())), promise: nil)
      }

      var trailers = trailers
      trailers.add(name: GRPCHeaderName.statusCode, value: String(describing: status.code.rawValue))
      if let message = status.message.flatMap(GRPCStatusMessageMarshaller.marshall) {
        trailers.add(name: GRPCHeaderName.statusMessage, value: message)
      }

      if contentType == .webTextProtobuf {
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

      // Log the call duration and status
      if let stopwatch = self.stopwatch {
        self.stopwatch = nil
        let millis = stopwatch.elapsedMillis()

        self.accessLog.debug("rpc call finished", metadata: [
          "duration_ms": "\(millis)",
          "status_code": "\(status.code.rawValue)"
        ])
      }

      self.outboundState = .ignore
      self.inboundState = .ignore
    }
  }
}

private extension HTTP1ToGRPCServerCodec {
  enum RequestEncodingValidation {
    /// The compression is not supported. The RPC should fail with an appropriate status and include
    /// our supported algorithms in the trailers.
    case unsupported

    /// Compression is supported.
    case supported(CompressionAlgorithm)

    /// Compression is supported but we did not disclose our support for it. We should continue but
    /// also send the acceptable compression methods (including the encoding the client specified)
    /// in the initial response metadata.
    case supportedButNotDisclosed(CompressionAlgorithm)
  }

  /// Validates the value of the 'grpc-encoding' header against compression algorithms supported and
  /// advertised by this peer.
  ///
  /// - Parameter requestEncoding: The value of the 'grpc-encoding' header.
  func validate(requestEncoding: String) -> RequestEncodingValidation {
    guard let algorithm = CompressionAlgorithm(rawValue: requestEncoding) else {
      return .unsupported
    }

    if self.encoding.enabled.contains(algorithm) {
      return .supported(algorithm)
    } else {
      return .supportedButNotDisclosed(algorithm)
    }
  }

  /// Makes a 'grpc-accept-encoding' header from the advertised encodings and an additional value
  /// if one is specified.
  func makeAcceptEncodingHeader(includeExtra extra: CompressionAlgorithm? = nil) -> String? {
    switch (self.encoding.enabled.isEmpty, extra) {
    case (false, .some(let extra)):
      return (self.encoding.enabled + CollectionOfOne(extra)).map { $0.name }.joined(separator: ",")
    case (false, .none):
      return self.encoding.enabled.map { $0.name }.joined(separator: ",")
    case (true, .some(let extra)):
      return extra.name
    case (true, .none):
      return nil
    }
  }

  /// Selects an appropriate response encoding from the list of encodings sent to us by the client.
  /// Returns `nil` if there were no appropriate algorithms, in which case the server will send
  /// messages uncompressed.
  func selectResponseEncoding(from acceptableEncoding: [Substring]) -> CompressionAlgorithm? {
    return acceptableEncoding.compactMap {
      CompressionAlgorithm(rawValue: String($0))
    }.first {
      self.encoding.enabled.contains($0)
    }
  }
}
