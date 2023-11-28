/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

import Atomics

/// A gRPC server.
///
/// The server accepts connections from clients and listens on each connection for new streams
/// which are initiated by the client. Each stream maps to a single RPC. The server routes accepted
/// streams to a service to handle the RPC or rejects them with an appropriate error if no service
/// can handle the RPC.
///
/// A ``GRPCServer`` may listen with multiple transports (for example, HTTP/2 and in-process) and route
/// requests from each transport to the same service instance. You can also use "interceptors",
/// to implement cross-cutting logic which apply to all accepted RPCs. Example uses of interceptors
/// include request filtering, authentication, and logging. Once requests have been intercepted
/// they are passed to a handler which in turn returns a response to send back to the client.
///
/// ## Creating and configuring a server
///
/// The following example demonstrates how to create and configure a server.
///
/// ```swift
/// let server = GRPCServer()
///
/// // Create and add an in-process transport.
/// let inProcessTransport = InProcessServerTransport()
/// server.transports.add(inProcessTransport)
///
/// // Create and register the 'Greeter' and 'Echo' services.
/// server.services.register(GreeterService())
/// server.services.register(EchoService())
///
/// // Create and add some interceptors.
/// server.interceptors.add(StatsRecordingServerInterceptors())
/// ```
///
/// ## Starting and stopping the server
///
/// Once you have configured the server call ``run()`` to start it. Calling ``run()`` starts each
/// of the server's transports. A ``ServerError`` is thrown if any of the transports can't be
/// started.
///
/// ```swift
/// // Start running the server.
/// try await server.run()
/// ```
///
/// The ``run()`` method won't return until the server has finished handling all requests. You can
/// signal to the server that it should stop accepting new requests by calling ``stopListening()``.
/// This allows the server to drain existing requests gracefully. To stop the server more abruptly
/// you can cancel the task running your server. If your application requires additional resources
/// that need their lifecycles managed you should consider using [Swift Service
/// Lifecycle](https://github.com/swift-server/swift-service-lifecycle).
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public final class GRPCServer: Sendable {
  typealias Stream = RPCStream<ServerTransport.Inbound, ServerTransport.Outbound>

  /// A collection of ``ServerTransport`` implementations that the server uses to listen
  /// for new requests.
  public var transports: Transports {
    get {
      self.storage.withLockedValue { $0.transports }
    }
    set {
      self.storage.withLockedValue { $0.transports = newValue }
    }
  }

  /// The services registered which the server is serving.
  public var services: Services {
    get {
      self.storage.withLockedValue { $0.services }
    }
    set {
      self.storage.withLockedValue { $0.services = newValue }
    }
  }

  /// A collection of ``ServerInterceptor`` implementations which are applied to all accepted
  /// RPCs.
  ///
  /// RPCs are intercepted in the order that interceptors are added. That is, a request received
  /// from the client will first be intercepted by the first added interceptor followed by the
  /// second, and so on.
  public var interceptors: Interceptors {
    get {
      self.storage.withLockedValue { $0.interceptors }
    }
    set {
      self.storage.withLockedValue { $0.interceptors = newValue }
    }
  }

  /// Underlying storage for the server.
  private struct Storage {
    var transports: Transports
    var services: Services
    var interceptors: Interceptors
    var state: State

    init() {
      self.transports = Transports()
      self.services = Services()
      self.interceptors = Interceptors()
      self.state = .notStarted
    }
  }

  private let storage: LockedValueBox<Storage>

  /// The state of the server.
  private enum State {
    /// The server hasn't been started yet. Can transition to `starting` or `stopped`.
    case notStarted
    /// The server is starting but isn't accepting requests yet. Can transition to `running`
    /// and `stopping`.
    case starting
    /// The server is running and accepting RPCs. Can transition to `stopping`.
    case running
    /// The server is stopping and no new RPCs will be accepted. Existing RPCs may run to
    /// completion. May transition to `stopped`.
    case stopping
    /// The server has stopped, no RPCs are in flight and no more will be accepted. This state
    /// is terminal.
    case stopped
  }

  /// Creates a new server with no resources.
  ///
  /// You can add resources to the server via ``transports-swift.property``,
  /// ``services-swift.property``, and ``interceptors-swift.property`` and start the server by
  /// calling ``run()``. Any changes to resources after ``run()`` has been called will be ignored.
  public init() {
    self.storage = LockedValueBox(Storage())
  }

  /// Starts the server and runs until all registered transports have closed.
  ///
  /// No RPCs are processed until all transports are listening. If a transport fails to start
  /// listening then all open transports are closed and a ``ServerError`` is thrown.
  ///
  /// This function returns when all transports have stopped listening and all requests have been
  /// handled. You can signal to transports that they should stop listening by calling
  /// ``stopListening()``. The server will continue to process existing requests.
  ///
  /// To stop the server more abruptly you can cancel the task that this function is running in.
  ///
  /// You must register all resources you wish to use with the server before calling this function
  /// as changes made after calling ``run()`` won't be reflected.
  ///
  /// - Note: You can only call this function once, repeated calls will result in a
  ///   ``ServerError`` being thrown.
  /// - Important: You must register at least one transport by calling
  ///   ``Transports-swift.struct/add(_:)`` before calling this method.
  public func run() async throws {
    let (transports, router, interceptors) = try self.storage.withLockedValue { storage in
      switch storage.state {
      case .notStarted:
        storage.state = .starting
        return (storage.transports, storage.services.router, storage.interceptors)

      case .starting, .running:
        throw ServerError(
          code: .serverIsAlreadyRunning,
          message: "The server is already running and can only be started once."
        )

      case .stopping, .stopped:
        throw ServerError(
          code: .serverIsStopped,
          message: "The server has stopped and can only be started once."
        )
      }
    }

    // When we exit this function we must have stopped.
    defer {
      self.storage.withLockedValue { $0.state = .stopped }
    }

    if transports.values.isEmpty {
      throw ServerError(
        code: .noTransportsConfigured,
        message: """
          Can't start server, no transports are configured. You must add at least one transport \
          to the server using 'transports.add(_:)' before calling 'run()'.
          """
      )
    }

    var listeners: [RPCAsyncSequence<Stream>] = []
    listeners.reserveCapacity(transports.values.count)

    for transport in transports.values {
      do {
        let listener = try await transport.listen()
        listeners.append(listener)
      } catch let cause {
        // Failed to start, so start stopping.
        self.storage.withLockedValue { $0.state = .stopping }
        // Some listeners may have started and have streams which need closing.
        await Self.rejectRequests(listeners, transports: transports)

        throw ServerError(
          code: .failedToStartTransport,
          message: """
            Server didn't start because the '\(type(of: transport))' transport threw an error \
            while starting.
            """,
          cause: cause
        )
      }
    }

    // May have been told to stop listening while starting the transports.
    let isStopping = self.storage.withLockedValue { storage in
      switch storage.state {
      case .notStarted, .running, .stopped:
        fatalError("Invalid state")

      case .starting:
        storage.state = .running
        return false

      case .stopping:
        return true
      }
    }

    // If the server is stopping then notify the transport and then consume them: there may be
    // streams opened at a lower level (e.g. HTTP/2) which are already open and need to be consumed.
    if isStopping {
      await Self.rejectRequests(listeners, transports: transports)
    } else {
      await Self.handleRequests(listeners, router: router, interceptors: interceptors)
    }
  }

  private static func rejectRequests(
    _ listeners: [RPCAsyncSequence<Stream>],
    transports: Transports
  ) async {
    // Tell the active listeners to stop listening.
    for transport in transports.values.prefix(listeners.count) {
      transport.stopListening()
    }

    // Drain any open streams on active listeners.
    await withTaskGroup(of: Void.self) { group in
      let unavailable = Status(
        code: .unavailable,
        message: "The server isn't ready to accept requests."
      )

      for listener in listeners {
        do {
          for try await stream in listener {
            group.addTask {
              try? await stream.outbound.write(.status(unavailable, [:]))
              stream.outbound.finish()
            }
          }
        } catch {
          // Suppress any errors, the original error from the transport which failed to start
          // should be thrown.
        }
      }
    }
  }

  private static func handleRequests(
    _ listeners: [RPCAsyncSequence<Stream>],
    router: RPCRouter,
    interceptors: Interceptors
  ) async {
    #if swift(>=5.9)
    if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
      await Self.handleRequestsInDiscardingTaskGroup(
        listeners,
        router: router,
        interceptors: interceptors
      )
    } else {
      await Self.handleRequestsInTaskGroup(listeners, router: router, interceptors: interceptors)
    }
    #else
    await Self.handleRequestsInTaskGroup(listeners, router: router, interceptors: interceptors)
    #endif
  }

  #if swift(>=5.9)
  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  private static func handleRequestsInDiscardingTaskGroup(
    _ listeners: [RPCAsyncSequence<Stream>],
    router: RPCRouter,
    interceptors: Interceptors
  ) async {
    await withDiscardingTaskGroup { group in
      for listener in listeners {
        group.addTask {
          await withDiscardingTaskGroup { subGroup in
            do {
              for try await stream in listener {
                subGroup.addTask {
                  await router.handle(stream: stream, interceptors: interceptors.values)
                }
              }
            } catch {
              // If the listener threw then the connection must be broken, cancel all work.
              subGroup.cancelAll()
            }
          }
        }
      }
    }
  }
  #endif

  private static func handleRequestsInTaskGroup(
    _ listeners: [RPCAsyncSequence<Stream>],
    router: RPCRouter,
    interceptors: Interceptors
  ) async {
    // If the discarding task group isn't available then fall back to using a regular task group
    // with a limit on subtasks. Most servers will use an HTTP/2 based transport, most
    // implementations limit connections to 100 concurrent streams. A limit of 4096 gives the server
    // scope to handle nearly 41 completely saturated connections.
    let maxConcurrentSubTasks = 4096
    let tasks = ManagedAtomic(0)

    await withTaskGroup(of: Void.self) { group in
      for listener in listeners {
        group.addTask {
          await withTaskGroup(of: Void.self) { subGroup in
            do {
              for try await stream in listener {
                let taskCount = tasks.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent)
                if taskCount >= maxConcurrentSubTasks {
                  _ = await subGroup.next()
                  tasks.wrappingDecrement(ordering: .sequentiallyConsistent)
                }

                subGroup.addTask {
                  await router.handle(stream: stream, interceptors: interceptors.values)
                }
              }
            } catch {
              // If the listener threw then the connection must be broken, cancel all work.
              subGroup.cancelAll()
            }
          }
        }
      }
    }
  }

  /// Signal to the server that it should stop listening for new requests.
  ///
  /// By calling this function you indicate to clients that they mustn't start new requests
  /// against this server. Once the server has processed all requests the ``run()`` method returns.
  ///
  /// Calling this on a server which is already stopping or has stopped has no effect.
  public func stopListening() {
    let transports = self.storage.withLockedValue { storage in
      let transports: Transports?

      switch storage.state {
      case .notStarted:
        storage.state = .stopped
        transports = nil
      case .starting:
        storage.state = .stopping
        transports = nil
      case .running:
        storage.state = .stopping
        transports = storage.transports
      case .stopping:
        transports = nil
      case .stopped:
        transports = nil
      }

      return transports
    }

    if let transports = transports?.values {
      for transport in transports {
        transport.stopListening()
      }
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCServer {
  /// The transports which provide a bidirectional communication channel with clients.
  ///
  /// You can add a new transport by calling ``add(_:)``.
  public struct Transports: Sendable {
    private(set) var values: [any (ServerTransport & Sendable)] = []

    /// Add a transport to the server.
    ///
    /// - Parameter transport: The transport to add.
    public mutating func add(_ transport: some (ServerTransport & Sendable)) {
      self.values.append(transport)
    }
  }

  /// The services registered with this server.
  ///
  /// You can register services by calling ``register(_:)`` or by manually adding handlers for
  /// methods to the ``router``.
  public struct Services: Sendable {
    /// The router storing handlers for known methods.
    public var router = RPCRouter()

    /// Registers service methods with the ``router``.
    ///
    /// - Parameter service: The service to register with the ``router``.
    public mutating func register(_ service: some RegistrableRPCService) {
      service.registerMethods(with: &self.router)
    }
  }

  /// A collection of interceptors providing cross-cutting functionality to each accepted RPC.
  public struct Interceptors: Sendable {
    private(set) var values: [any ServerInterceptor] = []

    /// Add an interceptor to the server.
    ///
    /// The order in which interceptors are added reflects the order in which they are called. The
    /// first interceptor added will be the first interceptor to intercept each request. The last
    /// interceptor added will be the final interceptor to intercept each request before calling
    /// the appropriate handler.
    ///
    /// - Parameter interceptor: The interceptor to add.
    public mutating func add(_ interceptor: some ServerInterceptor) {
      self.values.append(interceptor)
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCServer.Transports: CustomStringConvertible {
  public var description: String {
    return String(describing: self.values)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCServer.Services: CustomStringConvertible {
  public var description: String {
    // List the fully qualified all methods ordered by service and then method
    let rpcs = self.router.methods.map { $0.fullyQualifiedMethod }.sorted()
    return String(describing: rpcs)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCServer.Interceptors: CustomStringConvertible {
  public var description: String {
    return String(describing: self.values.map { String(describing: type(of: $0)) })
  }
}
