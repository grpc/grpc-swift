/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

#if canImport(NIOSSL)
import GRPCCore
import NIOCore
import NIOHTTP2
import NIOTLS
import NIOSSL

/// Configures a server pipeline for gRPC with the appropriate HTTP/2 handlers.
///
/// If TLS is enabled then the handler listens for a 'TLSUserEvent.handshakeCompleted' event and
/// configures the pipeline appropriately for the protocol negotiated via ALPN. If TLS is not
/// configured then the HTTP version is determined by parsing the inbound byte stream.
///
/// If anything other than an HTTP/2-like protocol is determined to have been negotiated, an error will be fired
/// down the pipeline and the channel will be closed, since we only support HTTP/2.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
internal final class HTTP2PipelineConfigurator: ChannelInboundHandler, RemovableChannelHandler {
  internal typealias InboundIn = ByteBuffer
  internal typealias InboundOut = ByteBuffer

  internal typealias HTTP2ConfiguratorResult = (
    ChannelPipeline.SynchronousOperations.HTTP2ConnectionChannel,
    ChannelPipeline.SynchronousOperations.HTTP2StreamMultiplexer
  )

  private var buffer: ByteBuffer?
  private var state: State

  private let configurationCompletePromise: EventLoopPromise<HTTP2ConfiguratorResult>
  private let compressionConfig: HTTP2ServerTransport.Config.Compression
  private let connectionConfig: HTTP2ServerTransport.Config.Connection
  private let http2Config: HTTP2ServerTransport.Config.HTTP2
  private let rpcConfig: HTTP2ServerTransport.Config.RPC

  private enum ALPN {
    /// ALPN is expected: this is an encrypted connection.
    case required

    /// ALPN is not expected: this is a cleartext connection.
    case notRequired
  }

  private enum State {
    case notConfigured(alpn: ALPN)
    case configuring
  }

  init(
    requireALPN: Bool,
    configurationCompletePromise: EventLoopPromise<HTTP2ConfiguratorResult>,
    compressionConfig: HTTP2ServerTransport.Config.Compression,
    connectionConfig: HTTP2ServerTransport.Config.Connection,
    http2Config: HTTP2ServerTransport.Config.HTTP2,
    rpcConfig: HTTP2ServerTransport.Config.RPC
  ) {
    if requireALPN {
      self.state = .notConfigured(alpn: .required)
    } else {
      self.state = .notConfigured(alpn: .notRequired)
    }
    self.configurationCompletePromise = configurationCompletePromise
    self.compressionConfig = compressionConfig
    self.connectionConfig = connectionConfig
    self.http2Config = http2Config
    self.rpcConfig = rpcConfig
  }

  private func configureHTTP2(context: ChannelHandlerContext, useTLS: Bool) {
    self.state = .configuring
    self.configurationCompleted(
      result: Result {
        try context.pipeline.syncOperations.configureGRPCServerPipeline(
          channel: context.channel,
          compressionConfig: self.compressionConfig,
          connectionConfig: self.connectionConfig,
          http2Config: self.http2Config,
          rpcConfig: self.rpcConfig,
          useTLS: useTLS
        )
      },
      context: context
    )
  }

  private func configurationCompleted(
    result: Result<HTTP2ConfiguratorResult, any Error>,
    context: ChannelHandlerContext
  ) {
    switch result {
    case .success(let configuratorResult):
      self.configurationCompletePromise.succeed(configuratorResult)
      context.pipeline.removeHandler(context: context, promise: nil)

    case let .failure(error):
      self.errorCaught(context: context, error: error)
      self.configurationCompletePromise.fail(error)
    }
  }

  // MARK: - Channel Handler

  internal func errorCaught(context: ChannelHandlerContext, error: any Error) {
    context.close(mode: .all, promise: nil)
  }

  internal func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    switch self.state {
    case .notConfigured(alpn: .required):
      if let event = event as? TLSUserEvent {
        self.handleHandshakeCompletedEvent(event, context: context)
      }

    case .notConfigured(alpn: .notRequired), .configuring:
      ()
    }

    context.fireUserInboundEventTriggered(event)
  }

  private func handleHandshakeCompletedEvent(
    _ event: TLSUserEvent,
    context: ChannelHandlerContext
  ) {
    switch event {
    case let .handshakeCompleted(negotiatedProtocol):
      switch negotiatedProtocol {
      case let .some(negotiated):
        if GRPCApplicationProtocolIdentifier.isHTTP2Like(negotiated) {
          self.configureHTTP2(context: context, useTLS: true)
        } else {
          // Either H1 was negotiated, which we don't support, or we got back an
          // unsupported ALPN identifier: close the channel.
          let error = RPCError(
            code: .internalError,
            message: "ALPN-negotiated protocol \(negotiated) is not HTTP2 and thus not supported."
          )
          self.configurationCompletePromise.fail(error)
          context.fireErrorCaught(error)
          context.close(mode: .all, promise: nil)
        }

      case .none:
        // No ALPN protocol negotiated but it was required: closing.
        let error = RPCError(
          code: .internalError,
          message: "ALPN resulted in no protocol being negotiated, but it was required."
        )
        self.configurationCompletePromise.fail(error)
        context.fireErrorCaught(error)
        context.close(mode: .all, promise: nil)
      }

    case .shutdownCompleted:
      // We don't care about this here.
      ()
    }
  }

  private func tryParsingBufferedData(context: ChannelHandlerContext) {
    if let buffer = self.buffer {
      switch HTTPVersionParser.determineHTTPVersion(buffer) {
      case .http2:
        // This is a plaintext connection.
        self.configureHTTP2(context: context, useTLS: false)
      case .http1OrUnknown:
        // The connection will be closed because of one of the following reasons:
        // - It was determined to be an H1 connection, which is unsupported by gRPC v2.
        // - The connection is neither H2 nor H1.
        let error = RPCError(
          code: .internalError,
          message: "Network protocol is not HTTP2 and thus is not supported."
        )
        self.configurationCompletePromise.fail(error)
        context.fireErrorCaught(error)
        context.close(mode: .all, promise: nil)
      case .notEnoughBytes:
        // Try again later with more bytes.
        ()
      }
    }
  }

  internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    var buffer = self.unwrapInboundIn(data)
    self.buffer.setOrWriteBuffer(&buffer)

    switch self.state {
    case .notConfigured(alpn: .notRequired):
      // If ALPN isn't required, then we can try parsing the data we just buffered.
      self.tryParsingBufferedData(context: context)

    case .notConfigured(alpn: .required), .configuring:
      // We expect ALPN or we're being configured: just buffer the data, we'll forward it later.
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

  static func prefixedWithHTTP2ConnectionPreface(_ buffer: ByteBuffer) -> SubParseResult {
    let view = buffer.readableBytesView

    guard view.count >= HTTPVersionParser.http2ClientMagic.count else {
      return .notEnoughBytes
    }

    let slice = view[view.startIndex ..< view.startIndex.advanced(by: self.http2ClientMagic.count)]
    return slice.elementsEqual(HTTPVersionParser.http2ClientMagic) ? .accepted : .rejected
  }

  enum ParseResult: Hashable {
    case http2
    case http1OrUnknown
    case notEnoughBytes
  }

  enum SubParseResult: Hashable {
    case accepted
    case rejected
    case notEnoughBytes
  }

  static func determineHTTPVersion(_ buffer: ByteBuffer) -> ParseResult {
    switch Self.prefixedWithHTTP2ConnectionPreface(buffer) {
    case .accepted:
      return .http2

    case .notEnoughBytes:
      return .notEnoughBytes

    case .rejected:
      return .http1OrUnknown
    }
  }
}

/// Application protocol identifiers for ALPN.
package enum GRPCApplicationProtocolIdentifier {
  static let gRPC = "grpc-exp"
  static let h2 = "h2"

  static func isHTTP2Like(_ value: String) -> Bool {
    switch value {
    case self.gRPC, self.h2:
      return true
    default:
      return false
    }
  }
}
#endif
