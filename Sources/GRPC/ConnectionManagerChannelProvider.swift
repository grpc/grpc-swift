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
import NIOPosix
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
  enum TLSMode {
    case configureWithNIOSSL(Result<NIOSSLContext, Error>)
    case configureWithNetworkFramework
    case disabled
  }

  internal var connectionTarget: ConnectionTarget
  internal var connectionKeepalive: ClientConnectionKeepalive
  internal var connectionIdleTimeout: TimeAmount

  internal var tlsMode: TLSMode
  internal var tlsConfiguration: GRPCTLSConfiguration?

  internal var httpTargetWindowSize: Int
  internal var httpMaxFrameSize: Int

  internal var errorDelegate: Optional<ClientErrorDelegate>
  internal var debugChannelInitializer: Optional<(Channel) -> EventLoopFuture<Void>>

  internal init(
    connectionTarget: ConnectionTarget,
    connectionKeepalive: ClientConnectionKeepalive,
    connectionIdleTimeout: TimeAmount,
    tlsMode: TLSMode,
    tlsConfiguration: GRPCTLSConfiguration?,
    httpTargetWindowSize: Int,
    httpMaxFrameSize: Int,
    errorDelegate: ClientErrorDelegate?,
    debugChannelInitializer: ((Channel) -> EventLoopFuture<Void>)?
  ) {
    self.connectionTarget = connectionTarget
    self.connectionKeepalive = connectionKeepalive
    self.connectionIdleTimeout = connectionIdleTimeout

    self.tlsMode = tlsMode
    self.tlsConfiguration = tlsConfiguration

    self.httpTargetWindowSize = httpTargetWindowSize
    self.httpMaxFrameSize = httpMaxFrameSize

    self.errorDelegate = errorDelegate
    self.debugChannelInitializer = debugChannelInitializer
  }

  internal init(configuration: ClientConnection.Configuration) {
    // Making a `NIOSSLContext` is expensive and we should only do it (at most) once per TLS
    // configuration. We do it now and store it in our `tlsMode` and surface any error during
    // channel creation (we're limited by our API in when we can throw any error).
    let tlsMode: TLSMode

    if let tlsConfiguration = configuration.tlsConfiguration {
      if tlsConfiguration.isNetworkFrameworkTLSBackend {
        tlsMode = .configureWithNetworkFramework
      } else {
        // The '!' is okay here, we have a `tlsConfiguration` (so we must be using TLS) and we know
        // it's not backed by Network.framework, so it must be backed by NIOSSL.
        tlsMode = .configureWithNIOSSL(Result { try tlsConfiguration.makeNIOSSLContext()! })
      }
    } else {
      tlsMode = .disabled
    }

    self.init(
      connectionTarget: configuration.target,
      connectionKeepalive: configuration.connectionKeepalive,
      connectionIdleTimeout: configuration.connectionIdleTimeout,
      tlsMode: tlsMode,
      tlsConfiguration: configuration.tlsConfiguration,
      httpTargetWindowSize: configuration.httpTargetWindowSize,
      httpMaxFrameSize: configuration.httpMaxFrameSize,
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

    var bootstrap = PlatformSupport.makeClientBootstrap(
      group: eventLoop,
      tlsConfiguration: self.tlsConfiguration,
      logger: logger
    )

    bootstrap = bootstrap
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
          switch self.tlsMode {
          case let .configureWithNIOSSL(sslContext):
            try sync.configureNIOSSLForGRPCClient(
              sslContext: sslContext,
              serverHostname: hostname,
              customVerificationCallback: self.tlsConfiguration?.nioSSLCustomVerificationCallback,
              logger: logger
            )

          // Network.framework TLS configuration is applied when creating the bootstrap so is a
          // no-op here.
          case .configureWithNetworkFramework,
               .disabled:
            ()
          }

          try sync.configureHTTP2AndGRPCHandlersForGRPCClient(
            channel: channel,
            connectionManager: connectionManager,
            connectionKeepalive: self.connectionKeepalive,
            connectionIdleTimeout: self.connectionIdleTimeout,
            httpTargetWindowSize: self.httpTargetWindowSize,
            httpMaxFrameSize: self.httpMaxFrameSize,
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
