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

extension ClientConnection {
  internal struct ChannelProvider {
    private var configuration: Configuration

    internal init(configuration: Configuration) {
      self.configuration = configuration
    }
  }
}

extension ClientConnection.ChannelProvider: ConnectionManagerChannelProvider {
  internal func makeChannel(
    managedBy connectionManager: ConnectionManager,
    onEventLoop eventLoop: EventLoop,
    connectTimeout: TimeAmount?,
    logger: Logger
  ) -> EventLoopFuture<Channel> {
    let serverHostname: String? = self.configuration.tls.flatMap { tls -> String? in
      if let hostnameOverride = tls.hostnameOverride {
        return hostnameOverride
      } else {
        return self.configuration.target.host
      }
    }.flatMap { hostname in
      if hostname.isIPAddress {
        return nil
      } else {
        return hostname
      }
    }

    let bootstrap = PlatformSupport.makeClientBootstrap(group: eventLoop, logger: logger)
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .channelInitializer { channel in
        let initialized = channel.configureGRPCClient(
          httpTargetWindowSize: self.configuration.httpTargetWindowSize,
          tlsConfiguration: self.configuration.tls?.configuration,
          tlsServerHostname: serverHostname,
          connectionManager: connectionManager,
          connectionKeepalive: self.configuration.connectionKeepalive,
          connectionIdleTimeout: self.configuration.connectionIdleTimeout,
          errorDelegate: self.configuration.errorDelegate,
          requiresZeroLengthWriteWorkaround: PlatformSupport.requiresZeroLengthWriteWorkaround(
            group: eventLoop,
            hasTLS: self.configuration.tls != nil
          ),
          logger: logger,
          customVerificationCallback: self.configuration.tls?.customVerificationCallback
        )

        // Run the debug initializer, if there is one.
        if let debugInitializer = self.configuration.debugChannelInitializer {
          return initialized.flatMap {
            debugInitializer(channel)
          }
        } else {
          return initialized
        }
      }

    if let connectTimeout = connectTimeout {
      _ = bootstrap.connectTimeout(connectTimeout)
    }

    return bootstrap.connect(to: self.configuration.target)
  }
}
