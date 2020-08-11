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
import Logging
import NIO
import NIOHTTP1
import NIOHTTP2

/// Channel handler that creates different processing pipelines depending on whether
/// the incoming request is HTTP 1 or 2.
internal class HTTPProtocolSwitcher {
  private let handlersInitializer: (Channel, Logger) -> EventLoopFuture<Void>
  private let errorDelegate: ServerErrorDelegate?
  private let logger: Logger
  private let httpTargetWindowSize: Int
  private let keepAlive: ServerConnectionKeepalive
  private let idleTimeout: TimeAmount

  // We could receive additional data after the initial data and before configuring
  // the pipeline; buffer it and fire it down the pipeline once it is configured.
  private enum State {
    case notConfigured
    case configuring
    case configured
  }

  private var state: State = .notConfigured
  private var bufferedData: [NIOAny] = []

  init(
    errorDelegate: ServerErrorDelegate?,
    httpTargetWindowSize: Int = 65535,
    keepAlive: ServerConnectionKeepalive,
    idleTimeout: TimeAmount,
    logger: Logger,
    handlersInitializer: @escaping (Channel, Logger) -> EventLoopFuture<Void>
  ) {
    self.errorDelegate = errorDelegate
    self.httpTargetWindowSize = httpTargetWindowSize
    self.keepAlive = keepAlive
    self.idleTimeout = idleTimeout
    self.logger = logger
    self.handlersInitializer = handlersInitializer
  }
}

extension HTTPProtocolSwitcher: ChannelInboundHandler, RemovableChannelHandler {
  typealias InboundIn = ByteBuffer
  typealias InboundOut = ByteBuffer

  enum HTTPProtocolVersionError: Error {
    /// Raised when it wasn't possible to detect HTTP Protocol version.
    case invalidHTTPProtocolVersion

    var localizedDescription: String {
      switch self {
      case .invalidHTTPProtocolVersion:
        return "Could not identify HTTP Protocol Version"
      }
    }
  }

  /// HTTP Protocol Version type
  enum HTTPProtocolVersion {
    case http1
    case http2
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.state {
    case .notConfigured:
      self.logger.debug("determining http protocol version")
      self.state = .configuring
      self.logger.debug("buffering data", metadata: ["data": "\(data)"])
      self.bufferedData.append(data)

      // Detect the HTTP protocol version for the incoming request, or error out if it
      // couldn't be detected.
      var inBuffer = self.unwrapInboundIn(data)
      guard let initialData = inBuffer.readString(length: inBuffer.readableBytes),
        let firstLine = initialData.split(
          separator: "\r\n",
          maxSplits: 1,
          omittingEmptySubsequences: true
        ).first else {
        self.logger.error("unable to determine http version")
        context.fireErrorCaught(HTTPProtocolVersionError.invalidHTTPProtocolVersion)
        return
      }

      let version: HTTPProtocolVersion

      if firstLine.contains("HTTP/2") {
        version = .http2
      } else if firstLine.contains("HTTP/1") {
        version = .http1
      } else {
        self.logger.error("unable to determine http version")
        context.fireErrorCaught(HTTPProtocolVersionError.invalidHTTPProtocolVersion)
        return
      }

      self.logger.debug("determined http version", metadata: ["http_version": "\(version)"])

      // Once configured remove ourself from the pipeline, or handle the error.
      let pipelineConfigured: EventLoopPromise<Void> = context.eventLoop.makePromise()
      pipelineConfigured.futureResult.whenComplete { result in
        switch result {
        case .success:
          context.pipeline.removeHandler(context: context, promise: nil)

        case let .failure(error):
          self.state = .notConfigured
          self.errorCaught(context: context, error: error)
        }
      }

      // Depending on whether it is HTTP1 or HTTP2, create different processing pipelines.
      // Inbound handlers in handlersInitializer should expect HTTPServerRequestPart objects
      // and outbound handlers should return HTTPServerResponsePart objects.
      switch version {
      case .http1:
        // Upgrade connections are not handled since gRPC connections already arrive in HTTP2,
        // while gRPC-Web does not support HTTP2 at all, so there are no compelling use cases
        // to support this.
        context.pipeline.configureHTTPServerPipeline(withErrorHandling: true)
          .flatMap { context.pipeline.addHandler(WebCORSHandler()) }
          .flatMap { self.handlersInitializer(context.channel, self.logger) }
          .cascade(to: pipelineConfigured)

      case .http2:
        context.channel.configureHTTP2Pipeline(
          mode: .server,
          targetWindowSize: self.httpTargetWindowSize
        ) { streamChannel in
          var logger = self.logger

          // Grab the streamID from the channel.
          return streamChannel.getOption(HTTP2StreamChannelOptions.streamID).map { streamID in
            logger[metadataKey: MetadataKey.streamID] = "\(streamID)"
            return logger
          }.recover { _ in
            logger[metadataKey: MetadataKey.streamID] = "<unknown>"
            return logger
          }.flatMap { logger in
            streamChannel.pipeline.addHandler(HTTP2FramePayloadToHTTP1ServerCodec()).flatMap {
              self.handlersInitializer(streamChannel, logger)
            }
          }
        }.flatMap { multiplexer -> EventLoopFuture<Void> in
          // Add a keepalive and idle handlers between the two HTTP2 handlers.
          let keepaliveHandler = GRPCServerKeepaliveHandler(configuration: self.keepAlive)
          let idleHandler = GRPCIdleHandler(mode: .server, idleTimeout: self.idleTimeout)
          return context.channel.pipeline.addHandlers(
            [keepaliveHandler, idleHandler],
            position: .before(multiplexer)
          )
        }
        .cascade(to: pipelineConfigured)
      }

    case .configuring:
      self.logger.debug("buffering data", metadata: ["data": "\(data)"])
      self.bufferedData.append(data)

    case .configured:
      self.logger
        .critical(
          "unexpectedly received data; this handler should have been removed from the pipeline"
        )
      assertionFailure(
        "unexpectedly received data; this handler should have been removed from the pipeline"
      )
    }
  }

  func removeHandler(
    context: ChannelHandlerContext,
    removalToken: ChannelHandlerContext.RemovalToken
  ) {
    self.logger.debug("unbuffering data")
    self.bufferedData.forEach {
      context.fireChannelRead($0)
    }

    context.leavePipeline(removalToken: removalToken)
    self.state = .configured
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    switch self.state {
    case .notConfigured, .configuring:
      let baseError: Error

      if let errorWithContext = error as? GRPCError.WithContext {
        baseError = errorWithContext.error
      } else {
        baseError = error
      }

      self.errorDelegate?.observeLibraryError(baseError)
      context.close(mode: .all, promise: nil)

    case .configured:
      // If we're configured we will rely on a handler further down the pipeline.
      context.fireErrorCaught(error)
    }
  }
}
