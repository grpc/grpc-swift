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
import Logging
import NIOCore
import NIOPosix
import NIOSSL
import NIOTransportServices

/// How a network implementation should be chosen.
public struct NetworkPreference: Hashable {
  private enum Wrapped: Hashable {
    case best
    case userDefined(NetworkImplementation)
  }

  private var wrapped: Wrapped
  private init(_ wrapped: Wrapped) {
    self.wrapped = wrapped
  }

  /// Use the best available, that is, Network.framework (and NIOTransportServices) when it is
  /// available on Darwin platforms (macOS 10.14+, iOS 12.0+, tvOS 12.0+, watchOS 6.0+), and
  /// falling back to the POSIX network model otherwise.
  public static let best = NetworkPreference(.best)

  /// Use the given implementation. Doing so may require additional availability checks depending
  /// on the implementation.
  public static func userDefined(_ implementation: NetworkImplementation) -> NetworkPreference {
    return NetworkPreference(.userDefined(implementation))
  }
}

/// The network implementation to use: POSIX sockets or Network.framework. This also determines
/// which variant of NIO to use; NIO or NIOTransportServices, respectively.
public struct NetworkImplementation: Hashable {
  fileprivate enum Wrapped: Hashable {
    case networkFramework
    case posix
  }

  fileprivate var wrapped: Wrapped
  private init(_ wrapped: Wrapped) {
    self.wrapped = wrapped
  }

  #if canImport(Network)
  /// Network.framework (NIOTransportServices).
  @available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
  public static let networkFramework = NetworkImplementation(.networkFramework)
  #endif

  /// POSIX (NIO).
  public static let posix = NetworkImplementation(.posix)

  internal static func matchingEventLoopGroup(_ group: EventLoopGroup) -> NetworkImplementation {
    #if canImport(Network)
    if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
      if PlatformSupport.isTransportServicesEventLoopGroup(group) {
        return .networkFramework
      }
    }
    #endif
    return .posix
  }
}

extension NetworkPreference {
  /// The network implementation, and by extension the NIO variant which will be used.
  ///
  /// Network.framework is available on macOS 10.14+, iOS 12.0+, tvOS 12.0+ and watchOS 6.0+.
  ///
  /// This isn't directly useful when implementing code which branches on the network preference
  /// since that code will still need the appropriate availability check:
  ///
  /// - `@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)`, or
  /// - `#available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)`.
  public var implementation: NetworkImplementation {
    switch self.wrapped {
    case .best:
      #if canImport(Network)
      if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
        return .networkFramework
      } else {
        // Older platforms must use the POSIX loop.
        return .posix
      }
      #else
      return .posix
      #endif

    case let .userDefined(implementation):
      return implementation
    }
  }
}

// MARK: - Generic Bootstraps

// TODO: Revisit the handling of NIO/NIOTS once https://github.com/apple/swift-nio/issues/796
// is addressed.

/// This protocol is intended as a layer of abstraction over `ClientBootstrap` and
/// `NIOTSConnectionBootstrap`.
public protocol ClientBootstrapProtocol {
  func connect(to: SocketAddress) -> EventLoopFuture<Channel>
  func connect(host: String, port: Int) -> EventLoopFuture<Channel>
  func connect(unixDomainSocketPath: String) -> EventLoopFuture<Channel>

  func connectTimeout(_ timeout: TimeAmount) -> Self
  func channelOption<T>(_ option: T, value: T.Value) -> Self where T: ChannelOption
  func channelInitializer(_ handler: @escaping (Channel) -> EventLoopFuture<Void>) -> Self
}

extension ClientBootstrap: ClientBootstrapProtocol {}

#if canImport(Network)
@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
extension NIOTSConnectionBootstrap: ClientBootstrapProtocol {}
#endif

/// This protocol is intended as a layer of abstraction over `ServerBootstrap` and
/// `NIOTSListenerBootstrap`.
public protocol ServerBootstrapProtocol {
  func bind(to: SocketAddress) -> EventLoopFuture<Channel>
  func bind(host: String, port: Int) -> EventLoopFuture<Channel>
  func bind(unixDomainSocketPath: String) -> EventLoopFuture<Channel>

  func serverChannelInitializer(_ initializer: @escaping (Channel) -> EventLoopFuture<Void>) -> Self
  func serverChannelOption<T>(_ option: T, value: T.Value) -> Self where T: ChannelOption

  func childChannelInitializer(_ initializer: @escaping (Channel) -> EventLoopFuture<Void>) -> Self
  func childChannelOption<T>(_ option: T, value: T.Value) -> Self where T: ChannelOption
}

extension ServerBootstrap: ServerBootstrapProtocol {}

#if canImport(Network)
@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
extension NIOTSListenerBootstrap: ServerBootstrapProtocol {}
#endif

// MARK: - Bootstrap / EventLoopGroup helpers

public enum PlatformSupport {
  /// Makes a new event loop group based on the network preference.
  ///
  /// If `.best` is chosen and `Network.framework` is available then `NIOTSEventLoopGroup` will
  /// be returned. A `MultiThreadedEventLoopGroup` will be returned otherwise.
  ///
  /// - Parameter loopCount: The number of event loops to create in the event loop group.
  /// - Parameter networkPreference: Network preference; defaulting to `.best`.
  public static func makeEventLoopGroup(
    loopCount: Int,
    networkPreference: NetworkPreference = .best,
    logger: Logger = Logger(label: "io.grpc", factory: { _ in SwiftLogNoOpLogHandler() })
  ) -> EventLoopGroup {
    logger.debug("making EventLoopGroup for \(networkPreference) network preference")
    switch networkPreference.implementation.wrapped {
    case .networkFramework:
      #if canImport(Network)
      guard #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else {
        logger.critical("Network.framework can be imported but is not supported on this platform")
        // This is gated by the availability of `.networkFramework` so should never happen.
        fatalError(".networkFramework is being used on an unsupported platform")
      }
      logger.debug("created NIOTSEventLoopGroup for \(networkPreference) preference")
      return NIOTSEventLoopGroup(loopCount: loopCount)
      #else
      fatalError(".networkFramework is being used on an unsupported platform")
      #endif
    case .posix:
      logger.debug("created MultiThreadedEventLoopGroup for \(networkPreference) preference")
      return MultiThreadedEventLoopGroup(numberOfThreads: loopCount)
    }
  }

  /// Makes a new client bootstrap using the given `EventLoopGroup`.
  ///
  /// If the `EventLoopGroup` is a `NIOTSEventLoopGroup` then the returned bootstrap will be a
  /// `NIOTSConnectionBootstrap`, otherwise it will be a `ClientBootstrap`.
  ///
  /// - Parameter group: The `EventLoopGroup` to use.
  public static func makeClientBootstrap(
    group: EventLoopGroup,
    logger: Logger = Logger(label: "io.grpc", factory: { _ in SwiftLogNoOpLogHandler() })
  ) -> ClientBootstrapProtocol {
    logger.debug("making client bootstrap with event loop group of type \(type(of: group))")
    #if canImport(Network)
    if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
      if isTransportServicesEventLoopGroup(group) {
        logger.debug(
          "Network.framework is available and the EventLoopGroup is compatible with NIOTS, creating a NIOTSConnectionBootstrap"
        )
        return NIOTSConnectionBootstrap(group: group)
      } else {
        logger.debug(
          "Network.framework is available but the EventLoopGroup is not compatible with NIOTS, falling back to ClientBootstrap"
        )
      }
    }
    #endif
    logger.debug("creating a ClientBootstrap")
    return ClientBootstrap(group: group)
  }

  internal static func isTransportServicesEventLoopGroup(_ group: EventLoopGroup) -> Bool {
    #if canImport(Network)
    if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
      return group is NIOTSEventLoopGroup || group is QoSEventLoop
    }
    #endif
    return false
  }

  internal static func makeClientBootstrap(
    group: EventLoopGroup,
    tlsConfiguration: GRPCTLSConfiguration?,
    logger: Logger
  ) -> ClientBootstrapProtocol {
    let bootstrap = self.makeClientBootstrap(group: group, logger: logger)

    guard let tlsConfigruation = tlsConfiguration else {
      return bootstrap
    }

    #if canImport(Network)
    if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *),
      let transportServicesBootstrap = bootstrap as? NIOTSConnectionBootstrap {
      return transportServicesBootstrap.tlsOptions(from: tlsConfigruation)
    }
    #endif

    return bootstrap
  }

  /// Makes a new server bootstrap using the given `EventLoopGroup`.
  ///
  /// If the `EventLoopGroup` is a `NIOTSEventLoopGroup` then the returned bootstrap will be a
  /// `NIOTSListenerBootstrap`, otherwise it will be a `ServerBootstrap`.
  ///
  /// - Parameter group: The `EventLoopGroup` to use.
  public static func makeServerBootstrap(
    group: EventLoopGroup,
    logger: Logger = Logger(label: "io.grpc", factory: { _ in SwiftLogNoOpLogHandler() })
  ) -> ServerBootstrapProtocol {
    logger.debug("making server bootstrap with event loop group of type \(type(of: group))")
    #if canImport(Network)
    if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
      if let tsGroup = group as? NIOTSEventLoopGroup {
        logger
          .debug(
            "Network.framework is available and the group is correctly typed, creating a NIOTSListenerBootstrap"
          )
        return NIOTSListenerBootstrap(group: tsGroup)
      } else if let qosEventLoop = group as? QoSEventLoop {
        logger
          .debug(
            "Network.framework is available and the group is correctly typed, creating a NIOTSListenerBootstrap"
          )
        return NIOTSListenerBootstrap(group: qosEventLoop)
      }
      logger
        .debug(
          "Network.framework is available but the group is not typed for NIOTS, falling back to ServerBootstrap"
        )
    }
    #endif
    logger.debug("creating a ServerBootstrap")
    return ServerBootstrap(group: group)
  }

  /// Determines whether we may need to work around an issue in Network.framework with zero-length writes.
  ///
  /// See https://github.com/apple/swift-nio-transport-services/pull/72 for more.
  static func requiresZeroLengthWriteWorkaround(group: EventLoopGroup, hasTLS: Bool) -> Bool {
    #if canImport(Network)
    if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
      if group is NIOTSEventLoopGroup || group is QoSEventLoop {
        // We need the zero-length write workaround on NIOTS when not using TLS.
        return !hasTLS
      } else {
        return false
      }
    } else {
      return false
    }
    #else
    return false
    #endif
  }
}

extension PlatformSupport {
  /// Make an `EventLoopGroup` which is compatible with the given TLS configuration/
  ///
  /// - Parameters:
  ///   - configuration: The configuration to make a compatible `EventLoopGroup` for.
  ///   - loopCount: The number of loops the `EventLoopGroup` should have.
  /// - Returns: An `EventLoopGroup` compatible with the given `configuration`.
  public static func makeEventLoopGroup(
    compatibleWith configuration: GRPCTLSConfiguration,
    loopCount: Int
  ) -> EventLoopGroup {
    #if canImport(Network)
    if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
      if configuration.isNetworkFrameworkTLSBackend {
        return NIOTSEventLoopGroup(loopCount: loopCount)
      }
    }
    #endif
    return MultiThreadedEventLoopGroup(numberOfThreads: loopCount)
  }
}

extension GRPCTLSConfiguration {
  /// Provides a `GRPCTLSConfiguration` suitable for the given `EventLoopGroup`.
  public static func makeClientDefault(
    compatibleWith eventLoopGroup: EventLoopGroup
  ) -> GRPCTLSConfiguration {
    let networkImplementation: NetworkImplementation = .matchingEventLoopGroup(eventLoopGroup)
    return GRPCTLSConfiguration.makeClientDefault(for: .userDefined(networkImplementation))
  }

  /// Provides a `GRPCTLSConfiguration` suitable for the given network preference.
  public static func makeClientDefault(
    for networkPreference: NetworkPreference
  ) -> GRPCTLSConfiguration {
    switch networkPreference.implementation.wrapped {
    case .networkFramework:
      #if canImport(Network)
      guard #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else {
        // This is gated by the availability of `.networkFramework` so should never happen.
        fatalError(".networkFramework is being used on an unsupported platform")
      }

      return .makeClientConfigurationBackedByNetworkFramework()
      #else
      fatalError(".networkFramework is being used on an unsupported platform")
      #endif

    case .posix:
      return .makeClientConfigurationBackedByNIOSSL()
    }
  }
}

extension EventLoopGroup {
  internal func isCompatible(with tlsConfiguration: GRPCTLSConfiguration) -> Bool {
    let isTransportServicesGroup = PlatformSupport.isTransportServicesEventLoopGroup(self)
    let isNetworkFrameworkTLSBackend = tlsConfiguration.isNetworkFrameworkTLSBackend
    // If the group is from NIOTransportServices then we can use either the NIOSSL or the
    // Network.framework TLS backend.
    //
    // If it isn't then we must not use the Network.Framework TLS backend.
    return isTransportServicesGroup || !isNetworkFrameworkTLSBackend
  }

  internal func preconditionCompatible(
    with tlsConfiguration: GRPCTLSConfiguration,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    precondition(
      self.isCompatible(with: tlsConfiguration),
      "Unsupported 'EventLoopGroup' and 'GRPCLSConfiguration' pairing (Network.framework backed TLS configurations MUST use an EventLoopGroup from NIOTransportServices)",
      file: file,
      line: line
    )
  }
}
