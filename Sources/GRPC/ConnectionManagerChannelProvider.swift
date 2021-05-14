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
import NIO
import NIOSSL

internal protocol ConnectionManagerChannelProvider {
  /// Make an `EventLoopFuture<Channel>`.
  ///
  /// - Parameters:
  ///   - connectionManager: The `ConnectionManager` requesting the `Channel`.
  ///   - eventLoop: The `EventLoop` to use for the`Channel`.
  ///   - connectTimeout: Optional connection timeout when starting the connection.
  ///   - logger: A logger.
  func makeChannel(
    managedBy connectionManager: ConnectionManager,
    onEventLoop eventLoop: EventLoop,
    connectTimeout: TimeAmount?,
    logger: Logger
  ) -> EventLoopFuture<Channel>
}

internal struct DefaultChannelProvider: ConnectionManagerChannelProvider {
  internal var connectionTarget: ConnectionTarget
  internal var connectionKeepalive: ClientConnectionKeepalive
  internal var connectionIdleTimeout: TimeAmount

  internal var sslContext: Result<NIOSSLContext, Error>?
  internal var tlsHostnameOverride: Optional<String>
  internal var tlsCustomVerificationCallback: Optional<NIOSSLCustomVerificationCallback>

  internal var httpTargetWindowSize: Int

  internal var errorDelegate: Optional<ClientErrorDelegate>
  internal var debugChannelInitializer: Optional<(Channel) -> EventLoopFuture<Void>>

  internal init(
    connectionTarget: ConnectionTarget,
    connectionKeepalive: ClientConnectionKeepalive,
    connectionIdleTimeout: TimeAmount,
    sslContext: Result<NIOSSLContext, Error>?,
    tlsHostnameOverride: String?,
    tlsCustomVerificationCallback: NIOSSLCustomVerificationCallback?,
    httpTargetWindowSize: Int,
    errorDelegate: ClientErrorDelegate?,
    debugChannelInitializer: ((Channel) -> EventLoopFuture<Void>)?
  ) {
    self.connectionTarget = connectionTarget
    self.connectionKeepalive = connectionKeepalive
    self.connectionIdleTimeout = connectionIdleTimeout

    self.sslContext = sslContext
    self.tlsHostnameOverride = tlsHostnameOverride
    self.tlsCustomVerificationCallback = tlsCustomVerificationCallback

    self.httpTargetWindowSize = httpTargetWindowSize

    self.errorDelegate = errorDelegate
    self.debugChannelInitializer = debugChannelInitializer
  }

  internal init(configuration: ClientConnection.Configuration) {
    // Making a `NIOSSLContext` is expensive and we should only do it (at most) once per TLS
    // configuration. We do it now and surface any error during channel creation (we're limited by
    // our API in when we can throw any error).
    let sslContext: Result<NIOSSLContext, Error>? = configuration.tls.map { tls in
      return Result {
        try NIOSSLContext(configuration: tls.configuration)
      }
    }

    self.init(
      connectionTarget: configuration.target,
      connectionKeepalive: configuration.connectionKeepalive,
      connectionIdleTimeout: configuration.connectionIdleTimeout,
      sslContext: sslContext,
      tlsHostnameOverride: configuration.tls?.hostnameOverride,
      tlsCustomVerificationCallback: configuration.tls?.customVerificationCallback,
      httpTargetWindowSize: configuration.httpTargetWindowSize,
      errorDelegate: configuration.errorDelegate,
      debugChannelInitializer: configuration.debugChannelInitializer
    )
  }

  private var serverHostname: String? {
    let hostname = self.tlsHostnameOverride ?? self.connectionTarget.host
    return hostname.isIPAddress ? nil : hostname
  }

  private var hasTLS: Bool {
    return self.sslContext != nil
  }

  private func requiresZeroLengthWorkaround(eventLoop: EventLoop) -> Bool {
    return PlatformSupport.requiresZeroLengthWriteWorkaround(group: eventLoop, hasTLS: self.hasTLS)
  }

  internal func makeChannel(
    managedBy connectionManager: ConnectionManager,
    onEventLoop eventLoop: EventLoop,
    connectTimeout: TimeAmount?,
    logger: Logger
  ) -> EventLoopFuture<Channel> {
    let hostname = self.serverHostname
    let needsZeroLengthWriteWorkaround = self.requiresZeroLengthWorkaround(eventLoop: eventLoop)

    let bootstrap = PlatformSupport.makeClientBootstrap(group: eventLoop, logger: logger)
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .channelInitializer { channel in
        let sync = channel.pipeline.syncOperations

        do {
          try sync.configureGRPCClient(
            channel: channel,
            httpTargetWindowSize: self.httpTargetWindowSize,
            sslContext: self.sslContext,
            tlsServerHostname: hostname,
            connectionManager: connectionManager,
            connectionKeepalive: self.connectionKeepalive,
            connectionIdleTimeout: self.connectionIdleTimeout,
            errorDelegate: self.errorDelegate,
            requiresZeroLengthWriteWorkaround: needsZeroLengthWriteWorkaround,
            logger: logger,
            customVerificationCallback: self.tlsCustomVerificationCallback
          )
        } catch {
          return channel.eventLoop.makeFailedFuture(error)
        }

        // Run the debug initializer, if there is one.
        if let debugInitializer = self.debugChannelInitializer {
          return debugInitializer(channel)
        } else {
          return channel.eventLoop.makeSucceededVoidFuture()
        }
      }

    if let connectTimeout = connectTimeout {
      _ = bootstrap.connectTimeout(connectTimeout)
    }

    return bootstrap.connect(to: self.connectionTarget)
  }
}
