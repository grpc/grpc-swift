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

/// A gRPC client.
///
/// A ``GRPCClient`` communicates to a server via a ``ClientTransport``.
///
/// You can start RPCs to the server by calling the corresponding method:
/// - ``unary(request:descriptor:serializer:deserializer:options:handler:)``
/// - ``clientStreaming(request:descriptor:serializer:deserializer:options:handler:)``
/// - ``serverStreaming(request:descriptor:serializer:deserializer:options:handler:)``
/// - ``bidirectionalStreaming(request:descriptor:serializer:deserializer:options:handler:)``
///
/// However, in most cases you should prefer wrapping the ``GRPCClient`` with a generated stub.
///
/// You can set ``ServiceConfig``s on this client to override whatever configurations have been
/// set on the given transport. You can also use ``ClientInterceptor``s to implement cross-cutting
/// logic which apply to all RPCs. Example uses of interceptors include authentication and logging.
///
/// ## Creating and configuring a client
///
/// The following example demonstrates how to create and configure a client.
///
/// ```swift
/// // Create a configuration object for the client and override the timeout for the 'Get' method on
/// // the 'echo.Echo' service. This configuration takes precedence over any set by the transport.
/// var configuration = GRPCClient.Configuration()
/// configuration.service.override = ServiceConfig(
///   methodConfig: [
///     MethodConfig(
///       names: [
///         MethodConfig.Name(service: "echo.Echo", method: "Get")
///       ],
///       timeout: .seconds(5)
///     )
///   ]
/// )
///
/// // Configure a fallback timeout for all RPCs (indicated by an empty service and method name) if
/// // no configuration is provided in the overrides or by the transport.
/// configuration.service.defaults = ServiceConfig(
///   methodConfig: [
///     MethodConfig(
///       names: [
///         MethodConfig.Name(service: "", method: "")
///       ],
///       timeout: .seconds(10)
///     )
///   ]
/// )
///
/// // Finally create a transport and instantiate the client, adding an interceptor.
/// let inProcessTransport = InProcessTransport()
///
/// let client = GRPCClient(
///   transport: inProcessTransport.client,
///   interceptors: [StatsRecordingClientInterceptor()],
///   configuration: configuration
/// )
/// ```
///
/// ## Starting and stopping the client
///
/// Once you have configured the client, call ``run()`` to start it. Calling ``run()`` instructs the
/// transport to start connecting to the server.
///
/// ```swift
/// // Start running the client. 'run()' must be running while RPCs are execute so it's executed in
/// // a task group.
/// try await withThrowingTaskGroup(of: Void.self) { group in
///   group.addTask {
///     try await client.run()
///   }
///
///   // Execute a request against the "echo.Echo" service.
///   try await client.unary(
///     request: ClientRequest.Single<[UInt8]>(message: [72, 101, 108, 108, 111, 33]),
///     descriptor: MethodDescriptor(service: "echo.Echo", method: "Get"),
///     serializer: IdentitySerializer(),
///     deserializer: IdentityDeserializer(),
///   ) { response in
///     print(response.message)
///   }
///
///   // The RPC has completed, close the client.
///   client.beginGracefulShutdown()
/// }
/// ```
///
/// The ``run()`` method won't return until the client has finished handling all requests. You can
/// signal to the client that it should stop creating new request streams by calling ``beginGracefulShutdown()``.
/// This gives the client enough time to drain any requests already in flight. To stop the client
/// more abruptly you can cancel the task running your client. If your application requires
/// additional resources that need their lifecycles managed you should consider using [Swift Service
/// Lifecycle](https://github.com/swift-server/swift-service-lifecycle).
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public final class GRPCClient: Sendable {
  /// The transport which provides a bidirectional communication channel with the server.
  private let transport: any ClientTransport

  /// A collection of interceptors providing cross-cutting functionality to each accepted RPC.
  ///
  /// The order in which interceptors are added reflects the order in which they are called. The
  /// first interceptor added will be the first interceptor to intercept each request. The last
  /// interceptor added will be the final interceptor to intercept each request before calling
  /// the appropriate handler.
  private let interceptors: [any ClientInterceptor]

  /// The current state of the client.
  private let state: Mutex<State>

  /// The state of the client.
  private enum State: Sendable {
    /// The client hasn't been started yet. Can transition to `running` or `stopped`.
    case notStarted
    /// The client is running and can send RPCs. Can transition to `stopping`.
    case running
    /// The client is stopping and no new RPCs will be sent. Existing RPCs may run to
    /// completion. May transition to `stopped`.
    case stopping
    /// The client has stopped, no RPCs are in flight and no more will be accepted. This state
    /// is terminal.
    case stopped

    mutating func run() throws {
      switch self {
      case .notStarted:
        self = .running

      case .running:
        throw RuntimeError(
          code: .clientIsAlreadyRunning,
          message: "The client is already running and can only be started once."
        )

      case .stopping, .stopped:
        throw RuntimeError(
          code: .clientIsStopped,
          message: "The client has stopped and can only be started once."
        )
      }
    }

    mutating func stopped() {
      self = .stopped
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
        return false
      }
    }

    func checkExecutable() throws {
      switch self {
      case .notStarted, .running:
        // Allow .notStarted as making a request can race with 'run()'. Transports should tolerate
        // queuing the request if not yet started.
        ()
      case .stopping, .stopped:
        throw RuntimeError(
          code: .clientIsStopped,
          message: "Client has been stopped. Can't make any more RPCs."
        )
      }
    }
  }

  /// Creates a new client with the given transport, interceptors and configuration.
  ///
  /// - Parameters:
  ///   - transport: The transport used to establish a communication channel with a server.
  ///   - interceptors: A collection of interceptors providing cross-cutting functionality to each
  ///       accepted RPC. The order in which interceptors are added reflects the order in which they
  ///       are called. The first interceptor added will be the first interceptor to intercept each
  ///       request. The last interceptor added will be the final interceptor to intercept each
  ///       request before calling the appropriate handler.
  public init(
    transport: some ClientTransport,
    interceptors: [any ClientInterceptor] = []
  ) {
    self.transport = transport
    self.interceptors = interceptors
    self.state = Mutex(.notStarted)
  }

  /// Start the client.
  ///
  /// This returns once ``beginGracefulShutdown()`` has been called and all in-flight RPCs have finished executing.
  /// If you need to abruptly stop all work you should cancel the task executing this method.
  ///
  /// The client, and by extension this function, can only be run once. If the client is already
  /// running or has already been closed then a ``RuntimeError`` is thrown.
  public func run() async throws {
    try self.state.withLock { try $0.run() }

    // When this function exits the client must have stopped.
    defer {
      self.state.withLock { $0.stopped() }
    }

    do {
      try await self.transport.connect()
    } catch {
      throw RuntimeError(
        code: .transportError,
        message: "The transport threw an error while connected.",
        cause: error
      )
    }
  }

  /// Close the client.
  ///
  /// The transport will be closed: this means that it will be given enough time to wait for
  /// in-flight RPCs to finish executing, but no new RPCs will be accepted. You can cancel the task
  /// executing ``run()`` if you want to abruptly stop in-flight RPCs.
  public func beginGracefulShutdown() {
    let wasRunning = self.state.withLock { $0.beginGracefulShutdown() }
    if wasRunning {
      self.transport.beginGracefulShutdown()
    }
  }

  /// Executes a unary RPC.
  ///
  /// - Parameters:
  ///   - request: The unary request.
  ///   - descriptor: The method descriptor for which to execute this request.
  ///   - serializer: A request serializer.
  ///   - deserializer: A response deserializer.
  ///   - options: Call specific options.
  ///   - handler: A unary response handler.
  ///
  /// - Returns: The return value from the `handler`.
  public func unary<Request, Response, ReturnValue: Sendable>(
    request: ClientRequest.Single<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    options: CallOptions,
    handler: @Sendable @escaping (ClientResponse.Single<Response>) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    try await self.bidirectionalStreaming(
      request: ClientRequest.Stream(single: request),
      descriptor: descriptor,
      serializer: serializer,
      deserializer: deserializer,
      options: options
    ) { stream in
      let singleResponse = await ClientResponse.Single(stream: stream)
      return try await handler(singleResponse)
    }
  }

  /// Start a client-streaming RPC.
  ///
  /// - Parameters:
  ///   - request: The request stream.
  ///   - descriptor: The method descriptor for which to execute this request.
  ///   - serializer: A request serializer.
  ///   - deserializer: A response deserializer.
  ///   - options: Call specific options.
  ///   - handler: A unary response handler.
  ///
  /// - Returns: The return value from the `handler`.
  public func clientStreaming<Request, Response, ReturnValue: Sendable>(
    request: ClientRequest.Stream<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    options: CallOptions,
    handler: @Sendable @escaping (ClientResponse.Single<Response>) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    try await self.bidirectionalStreaming(
      request: request,
      descriptor: descriptor,
      serializer: serializer,
      deserializer: deserializer,
      options: options
    ) { stream in
      let singleResponse = await ClientResponse.Single(stream: stream)
      return try await handler(singleResponse)
    }
  }

  /// Start a server-streaming RPC.
  ///
  /// - Parameters:
  ///   - request: The unary request.
  ///   - descriptor: The method descriptor for which to execute this request.
  ///   - serializer: A request serializer.
  ///   - deserializer: A response deserializer.
  ///   - options: Call specific options.
  ///   - handler: A response stream handler.
  ///
  /// - Returns: The return value from the `handler`.
  public func serverStreaming<Request, Response, ReturnValue: Sendable>(
    request: ClientRequest.Single<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    options: CallOptions,
    handler: @Sendable @escaping (ClientResponse.Stream<Response>) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    try await self.bidirectionalStreaming(
      request: ClientRequest.Stream(single: request),
      descriptor: descriptor,
      serializer: serializer,
      deserializer: deserializer,
      options: options,
      handler: handler
    )
  }

  /// Start a bidirectional streaming RPC.
  ///
  /// - Note: ``run()`` must have been called and still executing, and ``beginGracefulShutdown()`` mustn't
  /// have been called.
  ///
  /// - Parameters:
  ///   - request: The streaming request.
  ///   - descriptor: The method descriptor for which to execute this request.
  ///   - serializer: A request serializer.
  ///   - deserializer: A response deserializer.
  ///   - options: Call specific options.
  ///   - handler: A response stream handler.
  ///
  /// - Returns: The return value from the `handler`.
  public func bidirectionalStreaming<Request, Response, ReturnValue: Sendable>(
    request: ClientRequest.Stream<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    options: CallOptions,
    handler: @Sendable @escaping (ClientResponse.Stream<Response>) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    try self.state.withLock { try $0.checkExecutable() }
    let methodConfig = self.transport.config(forMethod: descriptor)
    var options = options
    options.formUnion(with: methodConfig)

    return try await ClientRPCExecutor.execute(
      request: request,
      method: descriptor,
      options: options,
      serializer: serializer,
      deserializer: deserializer,
      transport: self.transport,
      interceptors: self.interceptors,
      handler: handler
    )
  }
}
