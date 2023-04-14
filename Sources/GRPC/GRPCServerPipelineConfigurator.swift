/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import Logging
import NIOCore
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import NIOTLS

/// Configures a server pipeline for gRPC with the appropriate handlers depending on the HTTP
/// version used for transport.
///
/// If TLS is enabled then the handler listens for an 'TLSUserEvent.handshakeCompleted' event and
/// configures the pipeline appropriately for the protocol negotiated via ALPN. If TLS is not
/// configured then the HTTP version is determined by parsing the inbound byte stream.
final class GRPCServerPipelineConfigurator: ChannelInboundHandler, RemovableChannelHandler {
  internal typealias InboundIn = ByteBuffer
  internal typealias InboundOut = ByteBuffer

  /// The server configuration.
  private let configuration: Server.Configuration

  /// A buffer containing the buffered bytes.
  private var buffer: ByteBuffer?

  /// The current state.
  private var state: State

  private enum ALPN {
    /// ALPN is expected. It may or may not be required, however.
    case expected(required: Bool)

    /// ALPN was expected but not required and no protocol was negotiated in the handshake. We may
    /// now fall back to parsing bytes on the connection.
    case expectedButFallingBack

    /// ALPN is not expected; this is a cleartext connection.
    case notExpected
  }

  private enum State {
    /// The pipeline isn't configured yet.
    case notConfigured(alpn: ALPN)
    /// We're configuring the pipeline.
    case configuring
  }

  init(configuration: Server.Configuration) {
    if let tls = configuration.tlsConfiguration {
      self.state = .notConfigured(alpn: .expected(required: tls.requireALPN))
    } else {
      self.state = .notConfigured(alpn: .notExpected)
    }

    self.configuration = configuration
  }

  /// Makes a gRPC idle handler for the server..
  private func makeIdleHandler() -> GRPCIdleHandler {
    return .init(
      idleTimeout: self.configuration.connectionIdleTimeout,
      keepalive: self.configuration.connectionKeepalive,
      logger: self.configuration.logger
    )
  }

  /// Makes an HTTP/2 handler.
  private func makeHTTP2Handler(
    for channel: Channel,
    streamDelegate: NIOHTTP2StreamDelegate?
  ) -> NIOHTTP2Handler {
    var connectionConfiguration = NIOHTTP2Handler.ConnectionConfiguration()
    connectionConfiguration.initialSettings = [
      HTTP2Setting(
        parameter: .maxConcurrentStreams,
        value: self.configuration.httpMaxConcurrentStreams
      ),
      HTTP2Setting(
        parameter: .maxHeaderListSize,
        value: HPACKDecoder.defaultMaxHeaderListSize
      ),
      HTTP2Setting(
        parameter: .maxFrameSize,
        value: self.configuration.httpMaxFrameSize
      ),
      HTTP2Setting(
        parameter: .initialWindowSize,
        value: self.configuration.httpTargetWindowSize
      ),
    ]

    var streamConfiguration = NIOHTTP2Handler.StreamConfiguration()
    streamConfiguration.targetWindowSize = self.configuration.httpTargetWindowSize

    return .init(
      mode: .server,
      eventLoop: channel.eventLoop,
      connectionConfiguration: connectionConfiguration,
      streamConfiguration: streamConfiguration,
      streamDelegate: streamDelegate
    ) { stream in
      // Sync options were added to the HTTP/2 stream channel in 1.17.0 (we require at least this)
      // so this shouldn't be `nil`, but it's not a problem if it is.
      let http2StreamID = try? stream.syncOptions?.getOption(HTTP2StreamChannelOptions.streamID)
      let streamID = http2StreamID.map { streamID in
        return String(Int(streamID))
      } ?? "<unknown>"

      var logger = self.configuration.logger
      logger[metadataKey: MetadataKey.h2StreamID] = "\(streamID)"

      do {
        // TODO: provide user configuration for header normalization.
        let handler = self.makeHTTP2ToRawGRPCHandler(normalizeHeaders: true, logger: logger)
        try stream.pipeline.syncOperations.addHandler(handler)
        return stream.eventLoop.makeSucceededVoidFuture()
      } catch {
        return stream.eventLoop.makeFailedFuture(error)
      }
    }
  }

  /// Makes an HTTP/2 to raw gRPC server handler.
  private func makeHTTP2ToRawGRPCHandler(
    normalizeHeaders: Bool,
    logger: Logger
  ) -> HTTP2ToRawGRPCServerCodec {
    return HTTP2ToRawGRPCServerCodec(
      servicesByName: self.configuration.serviceProvidersByName,
      encoding: self.configuration.messageEncoding,
      errorDelegate: self.configuration.errorDelegate,
      normalizeHeaders: normalizeHeaders,
      maximumReceiveMessageLength: self.configuration.maximumReceiveMessageLength,
      logger: logger
    )
  }

  /// The pipeline finished configuring.
  private func configurationCompleted(result: Result<Void, Error>, context: ChannelHandlerContext) {
    switch result {
    case .success:
      context.pipeline.removeHandler(context: context, promise: nil)
    case let .failure(error):
      self.errorCaught(context: context, error: error)
    }
  }

  /// Configures the pipeline to handle gRPC requests on an HTTP/2 connection.
  private func configureHTTP2(context: ChannelHandlerContext) {
    // We're now configuring the pipeline.
    self.state = .configuring

    // We could use 'Channel.configureHTTP2Pipeline', but then we'd have to find the right handlers
    // to then insert our keepalive and idle handlers between. We can just add everything together.
    let result: Result<Void, Error>

    let idleHandler = self.makeIdleHandler()
    do {
      // This is only ever called as a result of reading a user inbound event or reading inbound so
      // we'll be on the right event loop and sync operations are fine.
      let sync = context.pipeline.syncOperations
      try sync.addHandler(self.makeHTTP2Handler(for: context.channel, streamDelegate: idleHandler))
      // Here we intentionally don't associate the multiplexer with the idleHandler in the server case
      try sync.addHandler(idleHandler)
      result = .success(())
    } catch {
      result = .failure(error)
    }

    self.configurationCompleted(result: result, context: context)
  }

  /// Configures the pipeline to handle gRPC-Web requests on an HTTP/1 connection.
  private func configureHTTP1(context: ChannelHandlerContext) {
    // We're now configuring the pipeline.
    self.state = .configuring

    let result: Result<Void, Error>
    do {
      // This is only ever called as a result of reading a user inbound event or reading inbound so
      // we'll be on the right event loop and sync operations are fine.
      let sync = context.pipeline.syncOperations
      try sync.configureHTTPServerPipeline(withErrorHandling: true)
      try sync.addHandler(WebCORSHandler(configuration: self.configuration.webCORS))
      let scheme = self.configuration.tlsConfiguration == nil ? "http" : "https"
      try sync.addHandler(GRPCWebToHTTP2ServerCodec(scheme: scheme))
      // There's no need to normalize headers for HTTP/1.
      try sync.addHandler(
        self.makeHTTP2ToRawGRPCHandler(normalizeHeaders: false, logger: self.configuration.logger)
      )
      result = .success(())
    } catch {
      result = .failure(error)
    }

    self.configurationCompleted(result: result, context: context)
  }

  /// Attempts to determine the HTTP version from the buffer and then configure the pipeline
  /// appropriately. Closes the connection if the HTTP version could not be determined.
  private func determineHTTPVersionAndConfigurePipeline(
    buffer: ByteBuffer,
    context: ChannelHandlerContext
  ) {
    switch HTTPVersionParser.determineHTTPVersion(buffer) {
    case .http2:
      self.configureHTTP2(context: context)
    case .http1:
      self.configureHTTP1(context: context)
    case .unknown:
      // Neither H2 nor H1 or the length limit has been exceeded.
      self.configuration.logger.error("Unable to determine http version, closing")
      context.close(mode: .all, promise: nil)
    case .notEnoughBytes:
      () // Try again with more bytes.
    }
  }

  /// Handles a 'TLSUserEvent.handshakeCompleted' event and configures the pipeline to handle gRPC
  /// requests.
  private func handleHandshakeCompletedEvent(
    _ event: TLSUserEvent,
    alpnIsRequired: Bool,
    context: ChannelHandlerContext
  ) {
    switch event {
    case let .handshakeCompleted(negotiatedProtocol):
      let tlsVersion = try? context.channel.getTLSVersionSync()
      self.configuration.logger.debug("TLS handshake completed", metadata: [
        "alpn": "\(negotiatedProtocol ?? "nil")",
        "tls_version": "\(tlsVersion.map(String.init(describing:)) ?? "nil")",
      ])

      switch negotiatedProtocol {
      case let .some(negotiated):
        if GRPCApplicationProtocolIdentifier.isHTTP2Like(negotiated) {
          self.configureHTTP2(context: context)
        } else if GRPCApplicationProtocolIdentifier.isHTTP1(negotiated) {
          self.configureHTTP1(context: context)
        } else {
          self.configuration.logger.warning("Unsupported ALPN identifier '\(negotiated)', closing")
          context.close(mode: .all, promise: nil)
        }

      case .none:
        if alpnIsRequired {
          self.configuration.logger.warning("No ALPN protocol negotiated, closing'")
          context.close(mode: .all, promise: nil)
        } else {
          self.configuration.logger.warning("No ALPN protocol negotiated'")
          // We're now falling back to parsing bytes.
          self.state = .notConfigured(alpn: .expectedButFallingBack)
          self.tryParsingBufferedData(context: context)
        }
      }

    case .shutdownCompleted:
      // We don't care about this here.
      ()
    }
  }

  /// Try to parse the buffered data to determine whether or not HTTP/2 or HTTP/1 should be used.
  private func tryParsingBufferedData(context: ChannelHandlerContext) {
    if let buffer = self.buffer {
      self.determineHTTPVersionAndConfigurePipeline(buffer: buffer, context: context)
    }
  }

  // MARK: - Channel Handler

  internal func errorCaught(context: ChannelHandlerContext, error: Error) {
    if let delegate = self.configuration.errorDelegate {
      let baseError: Error

      if let errorWithContext = error as? GRPCError.WithContext {
        baseError = errorWithContext.error
      } else {
        baseError = error
      }

      delegate.observeLibraryError(baseError)
    }

    context.close(mode: .all, promise: nil)
  }

  internal func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    switch self.state {
    case let .notConfigured(alpn: .expected(required)):
      if let event = event as? TLSUserEvent {
        self.handleHandshakeCompletedEvent(event, alpnIsRequired: required, context: context)
      }

    case .notConfigured(alpn: .expectedButFallingBack),
         .notConfigured(alpn: .notExpected),
         .configuring:
      ()
    }

    context.fireUserInboundEventTriggered(event)
  }

  internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    var buffer = self.unwrapInboundIn(data)
    self.buffer.setOrWriteBuffer(&buffer)

    switch self.state {
    case .notConfigured(alpn: .notExpected),
         .notConfigured(alpn: .expectedButFallingBack):
      // If ALPN isn't expected, or we didn't negotiate via ALPN and we don't require it then we
      // can try parsing the data we just buffered.
      self.tryParsingBufferedData(context: context)

    case .notConfigured(alpn: .expected),
         .configuring:
      // We expect ALPN or we're being configured, just buffer the data, we'll forward it later.
      ()
    }

    // Don't forward the reads: we'll do so when we have configured the pipeline.
  }

  internal func removeHandler(
    context: ChannelHandlerContext,
    removalToken: ChannelHandlerContext.RemovalToken
  ) {
    // Forward any buffered reads.
    if let buffer = self.buffer {
      self.buffer = nil
      context.fireChannelRead(self.wrapInboundOut(buffer))
    }
    context.leavePipeline(removalToken: removalToken)
  }
}

// MARK: - HTTP Version Parser

struct HTTPVersionParser {
  /// HTTP/2 connection preface bytes. See RFC 7540 § 5.3.
  private static let http2ClientMagic = [
    UInt8(ascii: "P"),
    UInt8(ascii: "R"),
    UInt8(ascii: "I"),
    UInt8(ascii: " "),
    UInt8(ascii: "*"),
    UInt8(ascii: " "),
    UInt8(ascii: "H"),
    UInt8(ascii: "T"),
    UInt8(ascii: "T"),
    UInt8(ascii: "P"),
    UInt8(ascii: "/"),
    UInt8(ascii: "2"),
    UInt8(ascii: "."),
    UInt8(ascii: "0"),
    UInt8(ascii: "\r"),
    UInt8(ascii: "\n"),
    UInt8(ascii: "\r"),
    UInt8(ascii: "\n"),
    UInt8(ascii: "S"),
    UInt8(ascii: "M"),
    UInt8(ascii: "\r"),
    UInt8(ascii: "\n"),
    UInt8(ascii: "\r"),
    UInt8(ascii: "\n"),
  ]

  /// Determines whether the bytes in the `ByteBuffer` are prefixed with the HTTP/2 client
  /// connection preface.
  static func prefixedWithHTTP2ConnectionPreface(_ buffer: ByteBuffer) -> SubParseResult {
    let view = buffer.readableBytesView

    guard view.count >= HTTPVersionParser.http2ClientMagic.count else {
      // Not enough bytes.
      return .notEnoughBytes
    }

    let slice = view[view.startIndex ..< view.startIndex.advanced(by: self.http2ClientMagic.count)]
    return slice.elementsEqual(HTTPVersionParser.http2ClientMagic) ? .accepted : .rejected
  }

  enum ParseResult: Hashable {
    case http1
    case http2
    case unknown
    case notEnoughBytes
  }

  enum SubParseResult: Hashable {
    case accepted
    case rejected
    case notEnoughBytes
  }

  private static let maxLengthToCheck = 1024

  static func determineHTTPVersion(_ buffer: ByteBuffer) -> ParseResult {
    switch Self.prefixedWithHTTP2ConnectionPreface(buffer) {
    case .accepted:
      return .http2

    case .notEnoughBytes:
      switch Self.prefixedWithHTTP1RequestLine(buffer) {
      case .accepted:
        // Not enough bytes to check H2, but enough to confirm H1.
        return .http1
      case .notEnoughBytes:
        // Not enough bytes to check H2 or H1.
        return .notEnoughBytes
      case .rejected:
        // Not enough bytes to check H2 and definitely not H1.
        return .notEnoughBytes
      }

    case .rejected:
      switch Self.prefixedWithHTTP1RequestLine(buffer) {
      case .accepted:
        // Not H2, but H1 is confirmed.
        return .http1
      case .notEnoughBytes:
        // Not H2, but not enough bytes to reject H1 yet.
        return .notEnoughBytes
      case .rejected:
        // Not H2 or H1.
        return .unknown
      }
    }
  }

  private static let http1_1 = [
    UInt8(ascii: "H"),
    UInt8(ascii: "T"),
    UInt8(ascii: "T"),
    UInt8(ascii: "P"),
    UInt8(ascii: "/"),
    UInt8(ascii: "1"),
    UInt8(ascii: "."),
    UInt8(ascii: "1"),
  ]

  /// Determines whether the bytes in the `ByteBuffer` are prefixed with an HTTP/1.1 request line.
  static func prefixedWithHTTP1RequestLine(_ buffer: ByteBuffer) -> SubParseResult {
    var readableBytesView = buffer.readableBytesView

    // We don't need to validate the request line, only determine whether we think it's an HTTP1
    // request line. Another handler will parse it properly.

    // From RFC 2616 § 5.1:
    //   Request-Line = Method SP Request-URI SP HTTP-Version CRLF

    // Get through the first space.
    guard readableBytesView.dropPrefix(through: UInt8(ascii: " ")) != nil else {
      let tooLong = buffer.readableBytes > Self.maxLengthToCheck
      return tooLong ? .rejected : .notEnoughBytes
    }

    // Get through the second space.
    guard readableBytesView.dropPrefix(through: UInt8(ascii: " ")) != nil else {
      let tooLong = buffer.readableBytes > Self.maxLengthToCheck
      return tooLong ? .rejected : .notEnoughBytes
    }

    // +2 for \r\n
    guard readableBytesView.count >= (Self.http1_1.count + 2) else {
      return .notEnoughBytes
    }

    guard let version = readableBytesView.dropPrefix(through: UInt8(ascii: "\r")),
          readableBytesView.first == UInt8(ascii: "\n") else {
      // If we didn't drop the prefix OR we did and the next byte wasn't '\n', then we had enough
      // bytes but the '\r\n' wasn't present: reject this as being HTTP1.
      return .rejected
    }

    return version.elementsEqual(Self.http1_1) ? .accepted : .rejected
  }
}

extension Collection where Self == Self.SubSequence, Self.Element: Equatable {
  /// Drops the prefix off the collection up to and including the first `separator`
  /// only if that separator appears in the collection.
  ///
  /// Returns the prefix up to but not including the separator if it was found, nil otherwise.
  mutating func dropPrefix(through separator: Element) -> SubSequence? {
    if self.isEmpty {
      return nil
    }

    guard let separatorIndex = self.firstIndex(of: separator) else {
      return nil
    }

    let prefix = self[..<separatorIndex]
    self = self[self.index(after: separatorIndex)...]
    return prefix
  }
}
