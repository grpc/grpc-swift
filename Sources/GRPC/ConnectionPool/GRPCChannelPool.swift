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

import struct Foundation.UUID

#if canImport(Network)
import Network
#endif

public enum GRPCChannelPool {
  /// Make a new ``GRPCChannel`` on which calls may be made to gRPC services.
  ///
  /// The channel is backed by one connection pool per event loop, each of which may make multiple
  /// connections to the given target. The size of the connection pool, and therefore the maximum
  /// number of connections it may create at a given time is determined by the number of event loops
  /// in the provided `EventLoopGroup` and the value of
  /// ``GRPCChannelPool/Configuration/ConnectionPool-swift.struct/connectionsPerEventLoop``.
  ///
  /// The event loop and therefore connection chosen for a call is determined by
  /// ``CallOptions/eventLoopPreference-swift.property``. If the `indifferent` preference is used
  /// then the least-used event loop is chosen and a connection on that event loop will be selected.
  /// If an `exact` preference is used then a connection on that event loop will be chosen provided
  /// the given event loop belongs to the `EventLoopGroup` used to create this ``GRPCChannel``.
  ///
  /// Each connection in the pool is initially idle, and no connections will be established until
  /// a call is made. The pool also closes connections after they have been inactive (i.e. are not
  /// being used for calls) for some period of time. This is determined by
  /// ``GRPCChannelPool/Configuration/idleTimeout``.
  ///
  /// > Important: The values of `transportSecurity` and `eventLoopGroup` **must** be compatible.
  /// >
  /// >   For ``GRPCChannelPool/Configuration/TransportSecurity-swift.struct/tls(_:)`` the allowed
  /// >   `EventLoopGroup`s depends on the value of ``GRPCTLSConfiguration``. If a TLS configuration
  /// >   is known ahead of time, ``PlatformSupport/makeEventLoopGroup(compatibleWith:loopCount:)``
  /// >   may be used to construct a compatible `EventLoopGroup`.
  /// >
  /// >   If the `EventLoopGroup` is known ahead of time then a default TLS configuration may be
  /// >   constructed with ``GRPCTLSConfiguration/makeClientDefault(compatibleWith:)``.
  /// >
  /// >   For ``GRPCChannelPool/Configuration/TransportSecurity-swift.struct/plaintext`` transport
  /// >   security both `MultiThreadedEventLoopGroup` and `NIOTSEventLoopGroup` (and `EventLoop`s
  /// >   from either) may be used.
  ///
  /// - Parameters:
  ///   - target: The target to connect to.
  ///   - transportSecurity: Transport layer security for connections.
  ///   - eventLoopGroup: The `EventLoopGroup` to run connections on.
  ///   - configure: A closure which may be used to modify defaulted configuration before
  ///        constructing the ``GRPCChannel``.
  /// - Throws: If it is not possible to construct an SSL context. This will never happen when
  ///     using the ``GRPCChannelPool/Configuration/TransportSecurity-swift.struct/plaintext``
  ///     transport security.
  /// - Returns: A ``GRPCChannel``.
  @inlinable
  public static func with(
    target: ConnectionTarget,
    transportSecurity: GRPCChannelPool.Configuration.TransportSecurity,
    eventLoopGroup: EventLoopGroup,
    _ configure: (inout GRPCChannelPool.Configuration) -> Void = { _ in }
  ) throws -> GRPCChannel {
    let configuration = GRPCChannelPool.Configuration.with(
      target: target,
      transportSecurity: transportSecurity,
      eventLoopGroup: eventLoopGroup,
      configure
    )

    return try PooledChannel(configuration: configuration)
  }

  /// See ``GRPCChannelPool/with(target:transportSecurity:eventLoopGroup:_:)``.
  public static func with(
    configuration: GRPCChannelPool.Configuration
  ) throws -> GRPCChannel {
    return try PooledChannel(configuration: configuration)
  }
}

extension GRPCChannelPool {
  public struct Configuration: Sendable {
    @inlinable
    internal init(
      target: ConnectionTarget,
      transportSecurity: TransportSecurity,
      eventLoopGroup: EventLoopGroup
    ) {
      self.target = target
      self.transportSecurity = transportSecurity
      self.eventLoopGroup = eventLoopGroup
    }

    // Note: we use `configure` blocks to avoid having to add new initializers when properties are
    // added to the configuration while allowing the configuration to be constructed as a constant.

    /// Construct and configure a ``GRPCChannelPool/Configuration``.
    ///
    /// - Parameters:
    ///   - target: The target to connect to.
    ///   - transportSecurity: Transport layer security for connections. Note that the value of
    ///       `eventLoopGroup` must be compatible with the value
    ///   - eventLoopGroup: The `EventLoopGroup` to run connections on.
    ///   - configure: A closure which may be used to modify defaulted configuration.
    @inlinable
    public static func with(
      target: ConnectionTarget,
      transportSecurity: TransportSecurity,
      eventLoopGroup: EventLoopGroup,
      _ configure: (inout Configuration) -> Void = { _ in }
    ) -> Configuration {
      var configuration = Configuration(
        target: target,
        transportSecurity: transportSecurity,
        eventLoopGroup: eventLoopGroup
      )
      configure(&configuration)
      return configuration
    }

    /// The target to connect to.
    public var target: ConnectionTarget

    /// Connection security.
    public var transportSecurity: TransportSecurity

    /// The `EventLoopGroup` used by the connection pool.
    public var eventLoopGroup: EventLoopGroup

    /// Connection pool configuration.
    public var connectionPool: ConnectionPool = .defaults

    /// HTTP/2 configuration.
    public var http2: HTTP2 = .defaults

    /// The connection backoff configuration.
    public var connectionBackoff = ConnectionBackoff()

    /// The amount of time to wait before closing the connection. The idle timeout will start only
    /// if there are no RPCs in progress and will be cancelled as soon as any RPCs start.
    ///
    /// If a connection becomes idle, starting a new RPC will automatically create a new connection.
    public var idleTimeout = TimeAmount.minutes(30)

    /// The maximum allowed age of a connection.
    ///
    /// If set, no new RPCs will be started on the connection after the connection has been opened
    /// for this period of time. Existing RPCs will be allowed to continue and the connection will
    /// close once all RPCs on the connection have finished. If this isn't set then connections have
    /// no limit on their lifetime.
    public var maxConnectionAge: TimeAmount? = nil

    /// The connection keepalive configuration.
    public var keepalive = ClientConnectionKeepalive()

    /// The maximum size in bytes of a message which may be received from a server. Defaults to 4MB.
    ///
    /// Any received messages whose size exceeds this limit will cause RPCs to fail with
    /// a `.resourceExhausted` status code.
    public var maximumReceiveMessageLength: Int = 4 * 1024 * 1024 {
      willSet {
        precondition(newValue >= 0, "maximumReceiveMessageLength must be positive")
      }
    }

    /// A channel initializer which will be run after gRPC has initialized each `NIOCore.Channel`.
    /// This may be used to add additional handlers to the pipeline and is intended for debugging.
    ///
    /// - Warning: The initializer closure may be invoked *multiple times*.
    @preconcurrency
    public var debugChannelInitializer: (@Sendable (Channel) -> EventLoopFuture<Void>)?

    /// An error delegate which is called when errors are caught.
    public var errorDelegate: ClientErrorDelegate?

    /// A delegate which will be notified about changes to the state of connections managed by the
    /// pool.
    public var delegate: GRPCConnectionPoolDelegate?

    /// The period at which connection pool stats are published to the ``delegate``.
    ///
    /// Ignored if either this value or ``delegate`` are `nil`.
    public var statsPeriod: TimeAmount?

    /// A logger used for background activity, such as connection state changes.
    public var backgroundActivityLogger = Logger(
      label: "io.grpc",
      factory: { _ in
        return SwiftLogNoOpLogHandler()
      }
    )

    #if canImport(Network)
    /// `TransportServices` related configuration. This will be ignored unless an appropriate event loop group
    /// (e.g. `NIOTSEventLoopGroup`) is used.
    public var transportServices: TransportServices = .defaults
    #endif
  }
}

extension GRPCChannelPool.Configuration {
  public struct TransportSecurity: Sendable {
    private init(_ configuration: GRPCTLSConfiguration?) {
      self.tlsConfiguration = configuration
    }

    /// The TLS configuration used. A `nil` value means that no TLS will be used and
    /// communication at the transport layer will be plaintext.
    public var tlsConfiguration: Optional<GRPCTLSConfiguration>

    /// Secure the transport layer with TLS.
    ///
    /// The TLS backend used depends on the value of `configuration`. See ``GRPCTLSConfiguration``
    /// for more details.
    ///
    /// > Important: the value of `configuration` **must** be compatible with
    /// > ``GRPCChannelPool/Configuration/eventLoopGroup``. See the documentation of
    /// > ``GRPCChannelPool/with(target:transportSecurity:eventLoopGroup:_:)`` for more details.
    public static func tls(_ configuration: GRPCTLSConfiguration) -> TransportSecurity {
      return TransportSecurity(configuration)
    }

    /// Insecure plaintext communication.
    public static let plaintext = TransportSecurity(nil)
  }
}

extension GRPCChannelPool.Configuration {
  public struct HTTP2: Hashable, Sendable {
    private static let allowedTargetWindowSizes = (1 ... Int(Int32.max))
    private static let allowedMaxFrameSizes = (1 << 14) ... ((1 << 24) - 1)

    /// Default HTTP/2 configuration.
    public static let defaults = HTTP2()

    @inlinable
    public static func with(_ configure: (inout HTTP2) -> Void) -> HTTP2 {
      var configuration = Self.defaults
      configure(&configuration)
      return configuration
    }

    /// The HTTP/2 max frame size. Defaults to 8MB. Values are clamped between 2^14 and 2^24-1
    /// octets inclusive (RFC 7540 § 4.2).
    public var targetWindowSize = 8 * 1024 * 1024 {
      didSet {
        self.targetWindowSize = self.targetWindowSize.clamped(to: Self.allowedTargetWindowSizes)
      }
    }

    /// The HTTP/2 max frame size. Defaults to 16384. Value is clamped between 2^14 and 2^24-1
    /// octets inclusive (the minimum and maximum allowable values - HTTP/2 RFC 7540 4.2).
    public var maxFrameSize: Int = 16384 {
      didSet {
        self.maxFrameSize = self.maxFrameSize.clamped(to: Self.allowedMaxFrameSizes)
      }
    }

    /// The HTTP/2 max number of reset streams. Defaults to 32. Must be non-negative.
    public var maxResetStreams: Int = 32 {
      willSet {
        precondition(newValue >= 0, "maxResetStreams must be non-negative")
      }
    }
  }
}

extension GRPCChannelPool.Configuration {
  public struct ConnectionPool: Hashable, Sendable {
    /// Default connection pool configuration.
    public static let defaults = ConnectionPool()

    @inlinable
    public static func with(_ configure: (inout ConnectionPool) -> Void) -> ConnectionPool {
      var configuration = Self.defaults
      configure(&configuration)
      return configuration
    }

    /// The maximum number of connections per `EventLoop` that may be created at a given time.
    ///
    /// Defaults to 1.
    public var connectionsPerEventLoop: Int = 1

    /// The maximum number of callers which may be waiting for a stream at any given time on a
    /// given `EventLoop`.
    ///
    /// Any requests for a stream which would cause this limit to be exceeded will be failed
    /// immediately.
    ///
    /// Defaults to 100.
    public var maxWaitersPerEventLoop: Int = 100

    /// The minimum number of connections to keep open in this pool, per EventLoop.
    /// This number of connections per EventLoop will never go idle and be closed.
    public var minConnectionsPerEventLoop: Int = 0

    /// The maximum amount of time a caller is willing to wait for a stream for before timing out.
    ///
    /// Defaults to 30 seconds.
    public var maxWaitTime: TimeAmount = .seconds(30)

    /// The threshold which, if exceeded, when creating a stream determines whether the pool will
    /// establish another connection (if doing so will not violate ``connectionsPerEventLoop``).
    ///
    /// The 'load' is calculated as the ratio of demand for streams (the sum of the number of
    /// waiters and the number of reserved streams) and the total number of streams which each
    /// thread _could support.
    public var reservationLoadThreshold: Double = 0.9
  }
}

#if canImport(Network)
extension GRPCChannelPool.Configuration {
  public struct TransportServices: Sendable {
    /// Default transport services configuration.
    public static let defaults = Self()

    @inlinable
    public static func with(_ configure: (inout Self) -> Void) -> Self {
      var configuration = Self.defaults
      configure(&configuration)
      return configuration
    }

    /// A closure allowing to customise the `NWParameters` used when establishing a connection using `NIOTransportServices`.
    @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
    public var nwParametersConfigurator: (@Sendable (NWParameters) -> Void)? {
      get {
        self._nwParametersConfigurator as! (@Sendable (NWParameters) -> Void)?
      }
      set {
        self._nwParametersConfigurator = newValue
      }
    }

    private var _nwParametersConfigurator: (any Sendable)?
  }
}
#endif  // canImport(Network)

/// The ID of a connection in the connection pool.
public struct GRPCConnectionID: Hashable, Sendable, CustomStringConvertible {
  private enum Value: Sendable, Hashable {
    case managerID(ConnectionManagerID)
    case uuid(UUID)
  }

  private let id: Value

  public var description: String {
    switch self.id {
    case .managerID(let id):
      return String(describing: id)
    case .uuid(let uuid):
      return String(describing: uuid)
    }
  }

  internal init(_ id: ConnectionManagerID) {
    self.id = .managerID(id)
  }

  /// Create a new unique connection ID.
  ///
  /// Normally you don't have to create connection IDs, gRPC will create them on your behalf.
  /// However creating them manually is useful when testing the ``GRPCConnectionPoolDelegate``.
  public init() {
    self.id = .uuid(UUID())
  }
}

/// A delegate for the connection pool which is notified of various lifecycle events.
///
/// All functions must execute quickly and may be executed on arbitrary threads. The implementor is
/// responsible for ensuring thread safety.
public protocol GRPCConnectionPoolDelegate: Sendable {
  /// A new connection was created with the given ID and added to the pool. The connection is not
  /// yet active (or connecting).
  ///
  /// In most cases ``startedConnecting(id:)`` will be the next function called for the given
  /// connection but ``connectionRemoved(id:)`` may also be called.
  func connectionAdded(id: GRPCConnectionID)

  /// The connection with the given ID was removed from the pool.
  func connectionRemoved(id: GRPCConnectionID)

  /// The connection with the given ID has started trying to establish a connection. The outcome
  /// of the connection will be reported as either ``connectSucceeded(id:streamCapacity:)`` or
  /// ``connectFailed(id:error:)``.
  func startedConnecting(id: GRPCConnectionID)

  /// A connection attempt failed with the given error. After some period of
  /// time ``startedConnecting(id:)`` may be called again.
  func connectFailed(id: GRPCConnectionID, error: Error)

  /// A connection was established on the connection with the given ID. `streamCapacity` streams are
  /// available to use on the connection. The maximum number of available streams may change over
  /// time and is reported via ``connectionUtilizationChanged(id:streamsUsed:streamCapacity:)``. The
  func connectSucceeded(id: GRPCConnectionID, streamCapacity: Int)

  /// The utilization of the connection changed; a stream may have been used, returned or the
  /// maximum number of concurrent streams available on the connection changed.
  func connectionUtilizationChanged(id: GRPCConnectionID, streamsUsed: Int, streamCapacity: Int)

  /// The remote peer is quiescing the connection: no new streams will be created on it. The
  /// connection will eventually be closed and removed from the pool.
  func connectionQuiescing(id: GRPCConnectionID)

  /// The connection was closed. The connection may be established again in the future (notified
  /// via ``startedConnecting(id:)``).
  func connectionClosed(id: GRPCConnectionID, error: Error?)

  /// Stats about the current state of the connection pool.
  ///
  /// Each ``GRPCConnectionPoolStats`` includes the stats for a sub-pool. Each sub-pool is tied
  /// to an `EventLoop`.
  ///
  /// Unlike the other delegate methods, this is called periodically based on the value
  /// of ``GRPCChannelPool/Configuration/statsPeriod``.
  func connectionPoolStats(_ stats: [GRPCSubPoolStats], id: GRPCConnectionPoolID)
}

extension GRPCConnectionPoolDelegate {
  public func connectionPoolStats(_ stats: [GRPCSubPoolStats], id: GRPCConnectionPoolID) {
    // Default conformance to avoid breaking changes.
  }
}

public struct GRPCSubPoolStats: Sendable, Hashable {
  public struct ConnectionStates: Sendable, Hashable {
    /// The number of idle connections.
    public var idle: Int
    /// The number of connections trying to establish a connection.
    public var connecting: Int
    /// The number of connections which are ready to use.
    public var ready: Int
    /// The number of connections which are backing off waiting to attempt to connect.
    public var transientFailure: Int

    public init() {
      self.idle = 0
      self.connecting = 0
      self.ready = 0
      self.transientFailure = 0
    }
  }

  /// The ID of the subpool.
  public var id: GRPCSubPoolID

  /// Counts of connection states.
  public var connectionStates: ConnectionStates

  /// The number of streams currently being used.
  public var streamsInUse: Int

  /// The number of streams which are currently free to use.
  ///
  /// The sum of this value and `streamsInUse` gives the capacity of the pool.
  public var streamsFreeToUse: Int

  /// The number of RPCs currently waiting for a stream.
  ///
  /// RPCs waiting for a stream are also known as 'waiters'.
  public var rpcsWaiting: Int

  public init(id: GRPCSubPoolID) {
    self.id = id
    self.connectionStates = ConnectionStates()
    self.streamsInUse = 0
    self.streamsFreeToUse = 0
    self.rpcsWaiting = 0
  }
}
