/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import NIOHTTP2
#if canImport(NIOSSL)
import NIOSSL
#endif
import SwiftProtobuf

@usableFromInline
internal final class PooledChannel: GRPCChannel {
  @usableFromInline
  internal let _configuration: GRPCChannelPool.Configuration
  @usableFromInline
  internal let _pool: PoolManager
  @usableFromInline
  internal let _authority: String
  @usableFromInline
  internal let _scheme: String

  @inlinable
  internal init(configuration: GRPCChannelPool.Configuration) throws {
    self._configuration = configuration
    self._authority = configuration.target.host

    let tlsMode: DefaultChannelProvider.TLSMode
    let scheme: String

    if let tlsConfiguration = configuration.transportSecurity.tlsConfiguration {
      scheme = "https"
      #if canImport(NIOSSL)
      if let sslContext = try tlsConfiguration.makeNIOSSLContext() {
        tlsMode = .configureWithNIOSSL(.success(sslContext))
      } else {
        #if canImport(Network)
        // - TLS is configured
        // - NIOSSL is available but we aren't using it
        // - Network.framework is available, we MUST be using that.
        tlsMode = .configureWithNetworkFramework
        #else
        // - TLS is configured
        // - NIOSSL is available but we aren't using it
        // - Network.framework is not available
        // NIOSSL or Network.framework must be available as TLS is configured.
        fatalError()
        #endif
      }
      #elseif canImport(Network)
      // - TLS is configured
      // - NIOSSL is not available
      // - Network.framework is available, we MUST be using that.
      tlsMode = .configureWithNetworkFramework
      #else
      // - TLS is configured
      // - NIOSSL is not available
      // - Network.framework is not available
      // NIOSSL or Network.framework must be available as TLS is configured.
      fatalError()
      #endif // canImport(NIOSSL)
    } else {
      scheme = "http"
      tlsMode = .disabled
    }

    self._scheme = scheme

    let provider = DefaultChannelProvider(
      connectionTarget: configuration.target,
      connectionKeepalive: configuration.keepalive,
      connectionIdleTimeout: configuration.idleTimeout,
      tlsMode: tlsMode,
      tlsConfiguration: configuration.transportSecurity.tlsConfiguration,
      httpTargetWindowSize: configuration.http2.targetWindowSize,
      httpMaxFrameSize: configuration.http2.targetWindowSize,
      errorDelegate: configuration.errorDelegate,
      debugChannelInitializer: configuration.debugChannelInitializer
    )

    self._pool = PoolManager.makeInitializedPoolManager(
      using: configuration.eventLoopGroup,
      perPoolConfiguration: .init(
        maxConnections: configuration.connectionPool.connectionsPerEventLoop,
        maxWaiters: configuration.connectionPool.maxWaitersPerEventLoop,
        loadThreshold: configuration.connectionPool.reservationLoadThreshold,
        assumedMaxConcurrentStreams: 100,
        connectionBackoff: configuration.connectionBackoff,
        channelProvider: provider
      ),
      logger: configuration.backgroundActivityLogger.wrapped
    )
  }

  @inlinable
  internal func _makeStreamChannel(
    callOptions: CallOptions
  ) -> (EventLoopFuture<Channel>, EventLoop) {
    let preferredEventLoop = callOptions.eventLoopPreference.exact
    let connectionWaitDeadline = NIODeadline.now() + self._configuration.connectionPool.maxWaitTime
    let deadline = min(callOptions.timeLimit.makeDeadline(), connectionWaitDeadline)

    let streamChannel = self._pool.makeStream(
      preferredEventLoop: preferredEventLoop,
      deadline: deadline,
      logger: GRPCLogger(wrapping: callOptions.logger)
    ) { channel in
      return channel.eventLoop.makeSucceededVoidFuture()
    }

    return (streamChannel.futureResult, preferredEventLoop ?? streamChannel.eventLoop)
  }

  // MARK: GRPCChannel conformance

  @inlinable
  internal func makeCall<Request, Response>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> where Request: Message, Response: Message {
    var callOptions = callOptions
    if let requestID = callOptions.requestIDProvider.requestID() {
      callOptions.applyRequestID(requestID)
    }

    let (stream, eventLoop) = self._makeStreamChannel(callOptions: callOptions)

    return Call(
      path: path,
      type: type,
      eventLoop: eventLoop,
      options: callOptions,
      interceptors: interceptors,
      transportFactory: .http2(
        channel: stream,
        authority: self._authority,
        scheme: self._scheme,
        maximumReceiveMessageLength: self._configuration.maximumReceiveMessageLength,
        errorDelegate: self._configuration.errorDelegate
      )
    )
  }

  @inlinable
  internal func makeCall<Request, Response>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> where Request: GRPCPayload, Response: GRPCPayload {
    var callOptions = callOptions
    if let requestID = callOptions.requestIDProvider.requestID() {
      callOptions.applyRequestID(requestID)
    }

    let (stream, eventLoop) = self._makeStreamChannel(callOptions: callOptions)

    return Call(
      path: path,
      type: type,
      eventLoop: eventLoop,
      options: callOptions,
      interceptors: interceptors,
      transportFactory: .http2(
        channel: stream,
        authority: self._authority,
        scheme: self._scheme,
        maximumReceiveMessageLength: self._configuration.maximumReceiveMessageLength,
        errorDelegate: self._configuration.errorDelegate
      )
    )
  }

  @inlinable
  internal func close(promise: EventLoopPromise<Void>) {
    self._pool.shutdown(mode: .forceful, promise: promise)
  }

  @inlinable
  internal func close() -> EventLoopFuture<Void> {
    let promise = self._configuration.eventLoopGroup.next().makePromise(of: Void.self)
    self.close(promise: promise)
    return promise.futureResult
  }

  @usableFromInline
  internal func closeGracefully(deadline: NIODeadline, promise: EventLoopPromise<Void>) {
    self._pool.shutdown(mode: .graceful(deadline), promise: promise)
  }
}

extension CallOptions {
  @usableFromInline
  mutating func applyRequestID(_ requestID: String) {
    self.logger[metadataKey: MetadataKey.requestID] = "\(requestID)"
    // Add the request ID header too.
    if let requestIDHeader = self.requestIDHeader {
      self.customMetadata.add(name: requestIDHeader, value: requestID)
    }
  }
}
