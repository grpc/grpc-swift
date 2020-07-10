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
import SwiftProtobuf

/// Incoming gRPC package with a fixed message type.
///
/// - Important: This is **NOT** part of the public API.
public enum _GRPCServerRequestPart<Request> {
  case head(HTTPRequestHead)
  case message(Request)
  case end
}

public typealias _RawGRPCServerRequestPart = _GRPCServerRequestPart<ByteBuffer>

/// Outgoing gRPC package with a fixed message type.
///
/// - Important: This is **NOT** part of the public API.
public enum _GRPCServerResponsePart<Response> {
  case headers(HTTPHeaders)
  case message(_MessageContext<Response>)
  case statusAndTrailers(GRPCStatus, HTTPHeaders)
}

public typealias _RawGRPCServerResponsePart = _GRPCServerResponsePart<ByteBuffer>

/// A simple channel handler that translates HTTP1 data types into gRPC packets, and vice versa.
///
/// We use HTTP1 (instead of HTTP2) primitives, as these are easier to work with than raw HTTP2
/// primitives while providing all the functionality we need. In addition, it allows us to support
/// gRPC-Web (gRPC over HTTP1).
///
/// The translation from HTTP2 to HTTP1 is done by `HTTP2ToHTTP1ServerCodec`.
public final class HTTP1ToGRPCServerCodec {
  public init(encoding: ServerMessageEncoding, logger: Logger) {
    self.encoding = encoding
    self.encodingHeaderValidator = MessageEncodingHeaderValidator(encoding: encoding)
    self.logger = logger

    var accessLog = Logger(subsystem: .serverAccess)
    accessLog[metadataKey: MetadataKey.requestID] = logger[metadataKey: MetadataKey.requestID]
    self.accessLog = accessLog
    self.messageReader = LengthPrefixedMessageReader()
    self.messageWriter = LengthPrefixedMessageWriter()
  }

  private var contentType: ContentType?

  private let encoding: ServerMessageEncoding
  private let encodingHeaderValidator: MessageEncodingHeaderValidator
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
  public typealias InboundOut = _RawGRPCServerRequestPart

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
    let encodingHeader = requestHead.headers.first(name: GRPCHeaderName.encoding)
    switch self.encodingHeaderValidator.validate(requestEncoding: encodingHeader) {
    case let .supported(algorithm, limit, acceptableEncoding):
      self.messageReader = LengthPrefixedMessageReader(compression: algorithm, decompressionLimit: limit)
      if acceptableEncoding.isEmpty {
        self.acceptEncodingHeader = nil
      } else {
        self.acceptEncodingHeader = acceptableEncoding.joined(separator: ",")
      }

    case .noCompression:
      self.messageReader = LengthPrefixedMessageReader()
      self.acceptEncodingHeader = nil

    case let .unsupported(header, acceptableEncoding):
      let message: String
      let headers: HTTPHeaders
      if acceptableEncoding.isEmpty {
        message = "compression is not supported"
        headers = .init()
      } else {
        let advertised = acceptableEncoding.joined(separator: ",")
        message = "'\(header)' compression is not supported, supported: \(advertised)"
        headers = [GRPCHeaderName.acceptEncoding: advertised]
      }

      let status = GRPCStatus(code: .unimplemented, message: message)
      defer {
        self.write(context: context, data: NIOAny(OutboundIn.statusAndTrailers(status, headers)), promise: nil)
        self.flush(context: context)
      }
      // We're about to fast-fail, so ignore any following inbound messages.
      return .ignore
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
    var requests: [ByteBuffer] = []
    do {
      while let buffer = try self.messageReader.nextMessage() {
        requests.append(buffer)
      }
    } catch let grpcError as GRPCError.WithContext {
      context.fireErrorCaught(grpcError)
      return .ignore
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
  public typealias OutboundIn = _RawGRPCServerResponsePart
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
            buffer: messageContext.message,
            into: &self.responseTextBuffer,
            compressed: messageContext.compressed
          )

          // Since we stored the written data, mark the write promise as successful so that the
          // ServerStreaming provider continues sending the data.
          promise?.succeed(())
        } else {
          let messageBuffer = try self.messageWriter.write(
            buffer: messageContext.message,
            allocator: context.channel.allocator,
            compressed: messageContext.compressed
          )
          context.write(self.wrapOutboundOut(.body(.byteBuffer(messageBuffer))), promise: promise)
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

fileprivate extension HTTP1ToGRPCServerCodec {
  /// Selects an appropriate response encoding from the list of encodings sent to us by the client.
  /// Returns `nil` if there were no appropriate algorithms, in which case the server will send
  /// messages uncompressed.
  func selectResponseEncoding(from acceptableEncoding: [Substring]) -> CompressionAlgorithm? {
    guard case .enabled(let configuration) = self.encoding else {
      return nil
    }

    return acceptableEncoding.compactMap {
      CompressionAlgorithm(rawValue: String($0))
    }.first {
      configuration.enabledAlgorithms.contains($0)
    }
  }
}

struct MessageEncodingHeaderValidator {
  var encoding: ServerMessageEncoding

  enum ValidationResult {
    /// The requested compression is supported.
    case supported(algorithm: CompressionAlgorithm, decompressionLimit: DecompressionLimit, acceptEncoding: [String])

    /// The `requestEncoding` is not supported; `acceptEncoding` contains all algorithms we do
    /// support.
    case unsupported(requestEncoding: String, acceptEncoding: [String])

    /// No compression was requested.
    case noCompression
  }

  /// Validates the value of the 'grpc-encoding' header against compression algorithms supported and
  /// advertised by this peer.
  ///
  /// - Parameter requestEncoding: The value of the 'grpc-encoding' header.
  func validate(requestEncoding: String?) -> ValidationResult {
    switch (self.encoding, requestEncoding) {
    // Compression is enabled and the client sent a message encoding header. Do we support it?
    case (.enabled(let configuration), .some(let header)):
      guard let algorithm = CompressionAlgorithm(rawValue: header) else {
        return .unsupported(
          requestEncoding: header,
          acceptEncoding: configuration.enabledAlgorithms.map { $0.name }
        )
      }

      if configuration.enabledAlgorithms.contains(algorithm) {
        return .supported(
          algorithm: algorithm,
          decompressionLimit: configuration.decompressionLimit,
          acceptEncoding: []
        )
      } else {
        // From: https://github.com/grpc/grpc/blob/master/doc/compression.md
        //
        //   Note that a peer MAY choose to not disclose all the encodings it supports. However, if
        //   it receives a message compressed in an undisclosed but supported encoding, it MUST
        //   include said encoding in the response's grpc-accept-encoding header.
        return .supported(
          algorithm: algorithm,
          decompressionLimit: configuration.decompressionLimit,
          acceptEncoding: configuration.enabledAlgorithms.map { $0.name } + CollectionOfOne(header)
        )
      }

    // Compression is disabled and the client sent a message encoding header. We clearly don't
    // support this. Note this is different to the supported but not advertised case since we have
    // explicitly not enabled compression.
    case (.disabled, .some(let header)):
      return .unsupported(requestEncoding: header, acceptEncoding: [])

    // The client didn't send a message encoding header.
    case (_, .none):
      return .noCompression
    }
  }
}
