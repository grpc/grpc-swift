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
import NIOTransportServices

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
  internal var tlsConfiguration: GRPCTLSConfiguration?

  internal var httpTargetWindowSize: Int

  internal var errorDelegate: Optional<ClientErrorDelegate>
  internal var debugChannelInitializer: Optional<(Channel) -> EventLoopFuture<Void>>

  internal init(
    connectionTarget: ConnectionTarget,
    connectionKeepalive: ClientConnectionKeepalive,
    connectionIdleTimeout: TimeAmount,
    sslContext: Result<NIOSSLContext, Error>?,
    tlsConfiguration: GRPCTLSConfiguration?,
    httpTargetWindowSize: Int,
    errorDelegate: ClientErrorDelegate?,
    debugChannelInitializer: ((Channel) -> EventLoopFuture<Void>)?
  ) {
    self.connectionTarget = connectionTarget
    self.connectionKeepalive = connectionKeepalive
    self.connectionIdleTimeout = connectionIdleTimeout

    self.sslContext = sslContext
    self.tlsConfiguration = tlsConfiguration

    self.httpTargetWindowSize = httpTargetWindowSize

    self.errorDelegate = errorDelegate
    self.debugChannelInitializer = debugChannelInitializer
  }

  internal init(configuration: ClientConnection.Configuration) {
    // Making a `NIOSSLContext` is expensive and we should only do it (at most) once per TLS
    // configuration. We do it now and surface any error during channel creation (we're limited by
    // our API in when we can throw any error).
    //
    // 'nil' means we're not using TLS, or we're using the Network.framework TLS backend. We'll
    // check and apply the Network.framework TLS options when we create a bootstrap.
    let sslContext: Result<NIOSSLContext, Error>?

    do {
      sslContext = try configuration.tlsConfiguration?.makeNIOSSLContext().map { .success($0) }
    } catch {
      sslContext = .failure(error)
    }

    self.init(
      connectionTarget: configuration.target,
      connectionKeepalive: configuration.connectionKeepalive,
      connectionIdleTimeout: configuration.connectionIdleTimeout,
      sslContext: sslContext,
      tlsConfiguration: configuration.tlsConfiguration,
      httpTargetWindowSize: configuration.httpTargetWindowSize,
      errorDelegate: configuration.errorDelegate,
      debugChannelInitializer: configuration.debugChannelInitializer
    )
  }

  private var serverHostname: String? {
    let hostname = self.tlsConfiguration?.hostnameOverride ?? self.connectionTarget.host
    return hostname.isIPAddress ? nil : hostname
  }

  private var hasTLS: Bool {
    return self.tlsConfiguration != nil
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

    let bootstrap = PlatformSupport.makeClientBootstrap(
      group: eventLoop,
      tlsConfiguration: self.tlsConfiguration,
      logger: logger
    )

    _ = bootstrap
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .channelInitializer { channel in
        let sync = channel.pipeline.syncOperations

        do {
          if needsZeroLengthWriteWorkaround {
            try sync.addHandler(NIOFilterEmptyWritesHandler())
          }

          // We have a NIOSSL context to apply. If we're using TLS from NIOTS then the bootstrap
          // will already have the TLS options applied.
          if let sslContext = self.sslContext {
            try sync.configureNIOSSLForGRPCClient(
              sslContext: sslContext,
              serverHostname: hostname,
              customVerificationCallback: self.tlsConfiguration?.nioSSLCustomVerificationCallback,
              logger: logger
            )
          }

          try sync.configureHTTP2AndGRPCHandlersForGRPCClient(
            channel: channel,
            connectionManager: connectionManager,
            connectionKeepalive: self.connectionKeepalive,
            connectionIdleTimeout: self.connectionIdleTimeout,
            httpTargetWindowSize: self.httpTargetWindowSize,
            errorDelegate: self.errorDelegate,
            logger: logger
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
