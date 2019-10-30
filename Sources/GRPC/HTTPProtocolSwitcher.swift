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
import NIOHTTP2
import Logging

/// Channel handler that creates different processing pipelines depending on whether
/// the incoming request is HTTP 1 or 2.
public class HTTPProtocolSwitcher {
  private let handlersInitializer: ((Channel) -> EventLoopFuture<Void>)
  private let errorDelegate: ServerErrorDelegate?
  private let logger = Logger(
    subsystem: .serverChannelCall,
    metadata: [MetadataKey.channelHandler: "HTTPProtocolSwitcher"]
  )

  // We could receive additional data after the initial data and before configuring
  // the pipeline; buffer it and fire it down the pipeline once it is configured.
  private enum State {
    case notConfigured
    case configuring
    case configured
  }

  private var state: State = .notConfigured {
    willSet {
      self.logger.info("state changed from '\(self.state)' to '\(newValue)'")
    }
  }
  private var bufferedData: [NIOAny] = []

  public init(errorDelegate: ServerErrorDelegate?, handlersInitializer: (@escaping (Channel) -> EventLoopFuture<Void>)) {
    self.errorDelegate = errorDelegate
    self.handlersInitializer = handlersInitializer
  }
}

extension HTTPProtocolSwitcher: ChannelInboundHandler, RemovableChannelHandler {
  public typealias InboundIn = ByteBuffer
  public typealias InboundOut = ByteBuffer

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

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.state {
    case .notConfigured:
      self.logger.info("determining http protocol version")
      self.state = .configuring
      self.logger.info("buffering data \(data)")
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

      self.logger.info("determined http version", metadata: ["http_version": "\(version)"])

      // Once configured remove ourself from the pipeline, or handle the error.
      let pipelineConfigured: EventLoopPromise<Void> = context.eventLoop.makePromise()
      pipelineConfigured.futureResult.whenComplete { result in
        switch result {
        case .success:
          context.pipeline.removeHandler(context: context, promise: nil)

        case .failure(let error):
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
          .flatMap { self.handlersInitializer(context.channel) }
          .cascade(to: pipelineConfigured)

      case .http2:
        context.channel.configureHTTP2Pipeline(mode: .server) { (streamChannel, streamID) in
            streamChannel.pipeline.addHandler(HTTP2ToHTTP1ServerCodec(streamID: streamID))
              .flatMap { self.handlersInitializer(streamChannel) }
          }
          .map { _ in }
          .cascade(to: pipelineConfigured)
      }

    case .configuring:
      self.logger.info("buffering data \(data)")
      self.bufferedData.append(data)

    case .configured:
      self.logger.critical("unexpectedly received data; this handler should have been removed from the pipeline")
      assertionFailure("unexpectedly received data; this handler should have been removed from the pipeline")
    }
  }

  public func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
    self.logger.info("unbuffering data")
    self.bufferedData.forEach {
      context.fireChannelRead($0)
    }

    context.leavePipeline(removalToken: removalToken)
    self.state = .configured
  }

  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    switch self.state {
    case .notConfigured, .configuring:
      errorDelegate?.observeLibraryError(error)
      context.close(mode: .all, promise: nil)

    case .configured:
      // If we're configured we will rely on a handler further down the pipeline.
      context.fireErrorCaught(error)
    }
  }
}
