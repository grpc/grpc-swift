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
import NIO
import NIOTransportServices
import Logging

/// How a network implementation should be chosen.
public enum NetworkPreference {
  /// Use the best available, that is, Network.framework (and NIOTransportServices) when it is
  /// available on Darwin platforms (macOS 10.14+, iOS 12.0+, tvOS 12.0+, watchOS 6.0+), and
  /// falling back to the POSIX network model otherwise.
  case best

  /// Use the given implementation. Doing so may require additional availability checks depending
  /// on the implementation.
  case userDefined(NetworkImplementation)
}

/// The network implementation to use: POSIX sockets or Network.framework. This also determines
/// which variant of NIO to use; NIO or NIOTransportServices, respectively.
public enum NetworkImplementation {
  #if canImport(Network)
  /// Network.framework (NIOTransportServices).
  @available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
  case networkFramework
  #endif
  /// POSIX (NIO).
  case posix
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
    switch self {
    case .best:
      #if canImport(Network)
      guard #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else {
        PlatformSupport.logger.critical("Network.framework can be imported but is not supported on this platform")
        // This is gated by the availability of `.networkFramework` so should never happen.
        fatalError(".networkFramework is being used on an unsupported platform")
      }
      PlatformSupport.logger.debug("'best' NetworkImplementation is .networkFramework")
      return .networkFramework
      #else
      PlatformSupport.logger.debug("'best' NetworkImplementation is .posix")
      return .posix
      #endif

    case .userDefined(let implementation):
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
  static let logger = Logger(subsystem: .nio)

  /// Makes a new event loop group based on the network preference.
  ///
  /// If `.best` is chosen and `Network.framework` is available then `NIOTSEventLoopGroup` will
  /// be returned. A `MultiThreadedEventLoopGroup` will be returned otherwise.
  ///
  /// - Parameter loopCount: The number of event loops to create in the event loop group.
  /// - Parameter networkPreference: Network prefernce; defaulting to `.best`.
  public static func makeEventLoopGroup(
    loopCount: Int,
    networkPreference: NetworkPreference = .best
  ) -> EventLoopGroup {
    logger.debug("making EventLoopGroup for \(networkPreference) network preference")
    switch networkPreference.implementation {
    #if canImport(Network)
    case .networkFramework:
      guard #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else {
        logger.critical("Network.framework can be imported but is not supported on this platform")
        // This is gated by the availability of `.networkFramework` so should never happen.
        fatalError(".networkFramework is being used on an unsupported platform")
      }
      logger.debug("created NIOTSEventLoopGroup for \(networkPreference) preference")
      return NIOTSEventLoopGroup(loopCount: loopCount)
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
  public static func makeClientBootstrap(group: EventLoopGroup) -> ClientBootstrapProtocol {
    logger.debug("making client bootstrap with event loop group of type \(type(of: group))")
    #if canImport(Network)
    if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
      if let tsGroup = group as? NIOTSEventLoopGroup {
        logger.debug("Network.framework is available and the group is correctly typed, creating a NIOTSConnectionBootstrap")
        return NIOTSConnectionBootstrap(group: tsGroup)
      } else if let qosEventLoop = group as? QoSEventLoop {
        logger.debug("Network.framework is available and the group is correctly typed, creating a NIOTSConnectionBootstrap")
        return NIOTSConnectionBootstrap(group: qosEventLoop)
      }
      logger.debug("Network.framework is available but the group is not typed for NIOTS, falling back to ClientBootstrap")
    }
    #endif
    logger.debug("creating a ClientBootstrap")
    return ClientBootstrap(group: group)
  }

  /// Makes a new server bootstrap using the given `EventLoopGroup`.
  ///
  /// If the `EventLoopGroup` is a `NIOTSEventLoopGroup` then the returned bootstrap will be a
  /// `NIOTSListenerBootstrap`, otherwise it will be a `ServerBootstrap`.
  ///
  /// - Parameter group: The `EventLoopGroup` to use.
  public static func makeServerBootstrap(group: EventLoopGroup) -> ServerBootstrapProtocol {
    logger.debug("making server bootstrap with event loop group of type \(type(of: group))")
    #if canImport(Network)
    if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
      if let tsGroup = group as? NIOTSEventLoopGroup {
        logger.debug("Network.framework is available and the group is correctly typed, creating a NIOTSListenerBootstrap")
        return NIOTSListenerBootstrap(group: tsGroup)
      } else if let qosEventLoop = group as? QoSEventLoop {
        logger.debug("Network.framework is available and the group is correctly typed, creating a NIOTSListenerBootstrap")
        return NIOTSListenerBootstrap(group: qosEventLoop)
      }
      logger.debug("Network.framework is available but the group is not typed for NIOTS, falling back to ServerBootstrap")
    }
    #endif
    logger.debug("creating a ServerBootstrap")
    return ServerBootstrap(group: group)
  }
}
