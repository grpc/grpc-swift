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

private import Synchronization

/// A gRPC server.
///
/// The server accepts connections from clients and listens on each connection for new streams
/// which are initiated by the client. Each stream maps to a single RPC. The server routes accepted
/// streams to a service to handle the RPC or rejects them with an appropriate error if no service
/// can handle the RPC.
///
/// A ``GRPCServer`` listens with a specific transport implementation (for example, HTTP/2 or in-process),
/// and routes requests from the transport to the service instance. You can also use "interceptors",
/// to implement cross-cutting logic which apply to all accepted RPCs. Example uses of interceptors
/// include request filtering, authentication, and logging. Once requests have been intercepted
/// they are passed to a handler which in turn returns a response to send back to the client.
///
/// ## Configuring and starting a server
///
/// The following example demonstrates how to create and run a server.
///
/// ```swift
/// // Create a transport
/// let transport = SomeServerTransport()
///
/// // Create the 'Greeter' and 'Echo' services.
/// let greeter = GreeterService()
/// let echo = EchoService()
///
/// // Create an interceptor.
/// let statsRecorder = StatsRecordingServerInterceptors()
///
/// // Run the server.
/// try await withGRPCServer(
///   transport: transport,
///   services: [greeter, echo],
///   interceptors: [statsRecorder]
/// ) { server in
///   // ...
///   // The server begins shutting down when this closure returns
///   // ...
/// }
/// ```
///
/// ## Creating a client manually
///
/// If the `with`-style methods for creating a server isn't suitable for your application then you
/// can create and run it manually. This requires you to call the ``serve()`` method in a task
/// which instructs the server to start its transport and listen for new RPCs. A ``RuntimeError`` is
/// thrown if the transport can't be started or encounters some other runtime error.
///
/// ```swift
/// // Start running the server.
/// try await server.serve()
/// ```
///
/// The ``serve()`` method won't return until the server has finished handling all requests. You can
/// signal to the server that it should stop accepting new requests by calling ``beginGracefulShutdown()``.
/// This allows the server to drain existing requests gracefully. To stop the server more abruptly
/// you can cancel the task running your server. If your application requires additional resources
/// that need their lifecycles managed you should consider using [Swift Service
/// Lifecycle](https://github.com/swift-server/swift-service-lifecycle) and the
/// `GRPCServiceLifecycle` module provided by [gRPC Swift Extras](https://github.com/grpc/grpc-swift-extras).
@available(gRPCSwift 2.0, *)
public final class GRPCServer<Transport: ServerTransport>: Sendable {
  typealias Stream = RPCStream<Transport.Inbound, Transport.Outbound>

  /// The ``ServerTransport`` implementation that the server uses to listen for new requests.
  public let transport: Transport

  /// The services registered which the server is serving.
  private let router: RPCRouter<Transport>

  /// The state of the server.
  private let state: Mutex<State>

  private enum State: Sendable {
    /// The server hasn't been started yet. Can transition to `running` or `stopped`.
    case notStarted
    /// The server is running and accepting RPCs. Can transition to `stopping`.
    case running
    /// The server is stopping and no new RPCs will be accepted. Existing RPCs may run to
    /// completion. May transition to `stopped`.
    case stopping
    /// The server has stopped, no RPCs are in flight and no more will be accepted. This state
    /// is terminal.
    case stopped

    mutating func startServing() throws {
      switch self {
      case .notStarted:
        self = .running

      case .running:
        throw RuntimeError(
          code: .serverIsAlreadyRunning,
          message: "The server is already running and can only be started once."
        )

      case .stopping, .stopped:
        throw RuntimeError(
          code: .serverIsStopped,
          message: "The server has stopped and can only be started once."
        )
      }
    }

    mutating func beginGracefulShutdown() -> Bool {
      switch self {
      case .notStarted:
        self = .stopped
        return false
      case .running:
        self = .stopping
        return true
      case .stopping, .stopped:
        // Already stopping/stopped, ignore.
        return false
      }
    }

    mutating func stopped() {
      self = .stopped
    }
  }

  /// Creates a new server.
  ///
  /// - Parameters:
  ///   - transport: The transport the server should listen on.
  ///   - services: Services offered by the server.
  ///   - interceptors: A collection of interceptors providing cross-cutting functionality to each
  ///       accepted RPC. The order in which interceptors are added reflects the order in which they
  ///       are called. The first interceptor added will be the first interceptor to intercept each
  ///       request. The last interceptor added will be the final interceptor to intercept each
  ///       request before calling the appropriate handler.
  public convenience init(
    transport: Transport,
    services: [any RegistrableRPCService],
    interceptors: [any ServerInterceptor] = []
  ) {
    self.init(
      transport: transport,
      services: services,
      interceptorPipeline: interceptors.map { .apply($0, to: .all) }
    )
  }

  /// Creates a new server.
  ///
  /// - Parameters:
  ///   - transport: The transport the server should listen on.
  ///   - services: Services offered by the server.
  ///   - interceptorPipeline: A collection of interceptors providing cross-cutting functionality to each
  ///       accepted RPC. The order in which interceptors are added reflects the order in which they
  ///       are called. The first interceptor added will be the first interceptor to intercept each
  ///       request. The last interceptor added will be the final interceptor to intercept each
  ///       request before calling the appropriate handler.
  public convenience init(
    transport: Transport,
    services: [any RegistrableRPCService],
    interceptorPipeline: [ConditionalInterceptor<any ServerInterceptor>]
  ) {
    var router = RPCRouter<Transport>()
    for service in services {
      service.registerMethods(with: &router)
    }
    router.registerInterceptors(pipeline: interceptorPipeline)

    self.init(transport: transport, router: router)
  }

  /// Creates a new server with a pre-configured router.
  ///
  /// - Parameters:
  ///   - transport: The transport the server should listen on.
  ///   - router: A ``RPCRouter`` used by the server to route accepted streams to method handlers.
  public init(transport: Transport, router: RPCRouter<Transport>) {
    self.state = Mutex(.notStarted)
    self.transport = transport
    self.router = router
  }

  /// Starts the server and runs until the registered transport has closed.
  ///
  /// No RPCs are processed until the configured transport is listening. If the transport fails to start
  /// listening, or if it encounters a runtime error, then ``RuntimeError`` is thrown.
  ///
  /// This function returns when the configured transport has stopped listening and all requests have been
  /// handled. You can signal to the transport that it should stop listening by calling
  /// ``beginGracefulShutdown()``. The server will continue to process existing requests.
  ///
  /// To stop the server more abruptly you can cancel the task that this function is running in.
  ///
  /// - Note: You can only call this function once, repeated calls will result in a
  ///   ``RuntimeError`` being thrown.
  public func serve() async throws {
    try self.state.withLock { try $0.startServing() }

    // When we exit this function the server must have stopped.
    defer {
      self.state.withLock { $0.stopped() }
    }

    do {
      try await transport.listen { stream, context in
        await self.router.handle(stream: stream, context: context)
      }
    } catch {
      throw RuntimeError(
        code: .transportError,
        message: "Server transport threw an error.",
        cause: error
      )
    }
  }

  /// Signal to the server that it should stop listening for new requests.
  ///
  /// By calling this function you indicate to clients that they mustn't start new requests
  /// against this server. Once the server has processed all requests the ``serve()`` method returns.
  ///
  /// Calling this on a server which is already stopping or has stopped has no effect.
  public func beginGracefulShutdown() {
    let wasRunning = self.state.withLock { $0.beginGracefulShutdown() }
    if wasRunning {
      self.transport.beginGracefulShutdown()
    }
  }
}

/// Creates and runs a gRPC server.
///
/// - Parameters:
///   - transport: The transport the server should listen on.
///   - services: Services offered by the server.
///   - interceptors: A collection of interceptors providing cross-cutting functionality to each
///       accepted RPC. The order in which interceptors are added reflects the order in which they
///       are called. The first interceptor added will be the first interceptor to intercept each
///       request. The last interceptor added will be the final interceptor to intercept each
///       request before calling the appropriate handler.
///   - isolation: A reference to the actor to which the enclosing code is isolated, or nil if the
///       code is nonisolated.
///   - handleServer: A closure which is called with the server. When the closure returns, the
///       server is shutdown gracefully.
/// - Returns: The result of the `handleServer` closure.
@available(gRPCSwift 2.0, *)
public func withGRPCServer<Transport: ServerTransport, Result: Sendable>(
  transport: Transport,
  services: [any RegistrableRPCService],
  interceptors: [any ServerInterceptor] = [],
  isolation: isolated (any Actor)? = #isolation,
  handleServer: (GRPCServer<Transport>) async throws -> Result
) async throws -> Result {
  try await withGRPCServer(
    transport: transport,
    services: services,
    interceptorPipeline: interceptors.map { .apply($0, to: .all) },
    isolation: isolation,
    handleServer: handleServer
  )
}

/// Creates and runs a gRPC server.
///
/// - Parameters:
///   - transport: The transport the server should listen on.
///   - services: Services offered by the server.
///   - interceptorPipeline: A collection of interceptors providing cross-cutting functionality to each
///       accepted RPC. The order in which interceptors are added reflects the order in which they
///       are called. The first interceptor added will be the first interceptor to intercept each
///       request. The last interceptor added will be the final interceptor to intercept each
///       request before calling the appropriate handler.
///   - isolation: A reference to the actor to which the enclosing code is isolated, or nil if the
///       code is nonisolated.
///   - handleServer: A closure which is called with the server. When the closure returns, the
///       server is shutdown gracefully.
/// - Returns: The result of the `handleServer` closure.
@available(gRPCSwift 2.0, *)
public func withGRPCServer<Transport: ServerTransport, Result: Sendable>(
  transport: Transport,
  services: [any RegistrableRPCService],
  interceptorPipeline: [ConditionalInterceptor<any ServerInterceptor>],
  isolation: isolated (any Actor)? = #isolation,
  handleServer: (GRPCServer<Transport>) async throws -> Result
) async throws -> Result {
  return try await withThrowingDiscardingTaskGroup { group in
    let server = GRPCServer(
      transport: transport,
      services: services,
      interceptorPipeline: interceptorPipeline
    )

    group.addTask {
      try await server.serve()
    }

    let result = try await handleServer(server)
    server.beginGracefulShutdown()
    return result
  }
}
