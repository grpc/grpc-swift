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
/// - ``unary(request:descriptor:serializer:deserializer:options:onResponse:)``
/// - ``clientStreaming(request:descriptor:serializer:deserializer:options:onResponse:)``
/// - ``serverStreaming(request:descriptor:serializer:deserializer:options:onResponse:)``
/// - ``bidirectionalStreaming(request:descriptor:serializer:deserializer:options:onResponse:)``
///
/// However, in most cases you should prefer wrapping the ``GRPCClient`` with a generated stub.
///
/// ## Creating a client
///
/// You can create and run a client using ``withGRPCClient(transport:interceptors:isolation:handleClient:)``
/// or ``withGRPCClient(transport:interceptorPipeline:isolation:handleClient:)`` which create, configure and
/// run the client providing scoped access to it via the `handleClient` closure. The client will
/// begin gracefully shutting down when the closure returns.
///
/// ```swift
/// let transport: any ClientTransport = ...
/// try await withGRPCClient(transport: transport) { client in
///   // ...
/// }
/// ```
///
/// ## Creating a client manually
///
/// If the `with`-style methods for creating clients isn't suitable for your application then you
/// can create and run a client manually. This requires you to call the ``run()`` method in a task
/// which instructs the client to start connecting to the server.
///
/// The ``run()`` method won't return until the client has finished handling all requests. You can
/// signal to the client that it should stop creating new request streams by calling ``beginGracefulShutdown()``.
/// This gives the client enough time to drain any requests already in flight. To stop the client
/// more abruptly you can cancel the task running your client. If your application requires
/// additional resources that need their lifecycles managed you should consider using [Swift Service
/// Lifecycle](https://github.com/swift-server/swift-service-lifecycle).
public final class GRPCClient: Sendable {
  /// The transport which provides a bidirectional communication channel with the server.
  private let transport: any ClientTransport

  /// The current state of the client.
  private let stateMachine: Mutex<StateMachine>

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

  private struct StateMachine {
    var state: State

    private let interceptorPipeline: [ConditionalInterceptor<any ClientInterceptor>]

    /// A collection of interceptors providing cross-cutting functionality to each accepted RPC, keyed by the method to which they apply.
    ///
    /// The list of interceptors for each method is computed from `interceptorsPipeline` when calling a method for the first time.
    /// This caching is done to avoid having to compute the applicable interceptors for each request made.
    ///
    /// The order in which interceptors are added reflects the order in which they are called. The
    /// first interceptor added will be the first interceptor to intercept each request. The last
    /// interceptor added will be the final interceptor to intercept each request before calling
    /// the appropriate handler.
    var interceptorsPerMethod: [MethodDescriptor: [any ClientInterceptor]]

    init(interceptorPipeline: [ConditionalInterceptor<any ClientInterceptor>]) {
      self.state = .notStarted
      self.interceptorPipeline = interceptorPipeline
      self.interceptorsPerMethod = [:]
    }

    mutating func checkExecutableAndGetApplicableInterceptors(
      for method: MethodDescriptor
    ) throws -> [any ClientInterceptor] {
      try self.state.checkExecutable()

      guard let applicableInterceptors = self.interceptorsPerMethod[method] else {
        let applicableInterceptors = self.interceptorPipeline
          .filter { $0.applies(to: method) }
          .map { $0.interceptor }
        self.interceptorsPerMethod[method] = applicableInterceptors
        return applicableInterceptors
      }

      return applicableInterceptors
    }
  }

  /// Creates a new client with the given transport, interceptors and configuration.
  ///
  /// - Parameters:
  ///   - transport: The transport used to establish a communication channel with a server.
  ///   - interceptors: A collection of ``ClientInterceptor``s providing cross-cutting functionality to each
  ///       accepted RPC. The order in which interceptors are added reflects the order in which they
  ///       are called. The first interceptor added will be the first interceptor to intercept each
  ///       request. The last interceptor added will be the final interceptor to intercept each
  ///       request before calling the appropriate handler.
  convenience public init(
    transport: some ClientTransport,
    interceptors: [any ClientInterceptor] = []
  ) {
    self.init(
      transport: transport,
      interceptorPipeline: interceptors.map { .apply($0, to: .all) }
    )
  }

  /// Creates a new client with the given transport, interceptors and configuration.
  ///
  /// - Parameters:
  ///   - transport: The transport used to establish a communication channel with a server.
  ///   - interceptorPipeline: A collection of ``ClientInterceptorPipelineOperation`` providing cross-cutting
  ///       functionality to each accepted RPC. Only applicable interceptors from the pipeline will be applied to each RPC.
  ///       The order in which interceptors are added reflects the order in which they are called.
  ///       The first interceptor added will be the first interceptor to intercept each request.
  ///       The last interceptor added will be the final interceptor to intercept each request before calling the appropriate handler.
  public init(
    transport: some ClientTransport,
    interceptorPipeline: [ConditionalInterceptor<any ClientInterceptor>]
  ) {
    self.transport = transport
    self.stateMachine = Mutex(StateMachine(interceptorPipeline: interceptorPipeline))
  }

  /// Start the client.
  ///
  /// This returns once ``beginGracefulShutdown()`` has been called and all in-flight RPCs have finished executing.
  /// If you need to abruptly stop all work you should cancel the task executing this method.
  ///
  /// The client, and by extension this function, can only be run once. If the client is already
  /// running or has already been closed then a ``RuntimeError`` is thrown.
  public func run() async throws {
    try self.stateMachine.withLock { try $0.state.run() }

    // When this function exits the client must have stopped.
    defer {
      self.stateMachine.withLock { $0.state.stopped() }
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
    let wasRunning = self.stateMachine.withLock { $0.state.beginGracefulShutdown() }
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
  ///   - handleResponse: A unary response handler.
  ///
  /// - Returns: The return value from the `handleResponse`.
  public func unary<Request, Response, ReturnValue: Sendable>(
    request: ClientRequest<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    options: CallOptions,
    onResponse handleResponse: @Sendable @escaping (
      _ response: ClientResponse<Response>
    ) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    try await self.bidirectionalStreaming(
      request: StreamingClientRequest(single: request),
      descriptor: descriptor,
      serializer: serializer,
      deserializer: deserializer,
      options: options
    ) { stream in
      let singleResponse = await ClientResponse(stream: stream)
      return try await handleResponse(singleResponse)
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
  ///   - handleResponse: A unary response handler.
  ///
  /// - Returns: The return value from the `handleResponse`.
  public func clientStreaming<Request, Response, ReturnValue: Sendable>(
    request: StreamingClientRequest<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    options: CallOptions,
    onResponse handleResponse: @Sendable @escaping (
      _ response: ClientResponse<Response>
    ) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    try await self.bidirectionalStreaming(
      request: request,
      descriptor: descriptor,
      serializer: serializer,
      deserializer: deserializer,
      options: options
    ) { stream in
      let singleResponse = await ClientResponse(stream: stream)
      return try await handleResponse(singleResponse)
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
  ///   - handleResponse: A response stream handler.
  ///
  /// - Returns: The return value from the `handleResponse`.
  public func serverStreaming<Request, Response, ReturnValue: Sendable>(
    request: ClientRequest<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    options: CallOptions,
    onResponse handleResponse: @Sendable @escaping (
      _ response: StreamingClientResponse<Response>
    ) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    try await self.bidirectionalStreaming(
      request: StreamingClientRequest(single: request),
      descriptor: descriptor,
      serializer: serializer,
      deserializer: deserializer,
      options: options,
      onResponse: handleResponse
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
  ///   - handleResponse: A response stream handler.
  ///
  /// - Returns: The return value from the `handleResponse`.
  public func bidirectionalStreaming<Request, Response, ReturnValue: Sendable>(
    request: StreamingClientRequest<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    options: CallOptions,
    onResponse handleResponse: @Sendable @escaping (
      _ response: StreamingClientResponse<Response>
    ) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    let applicableInterceptors = try self.stateMachine.withLock {
      try $0.checkExecutableAndGetApplicableInterceptors(for: descriptor)
    }
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
      interceptors: applicableInterceptors,
      handler: handleResponse
    )
  }
}

/// Creates and runs a new client with the given transport and interceptors.
///
/// - Parameters:
///   - transport: The transport used to establish a communication channel with a server.
///   - interceptors: A collection of ``ClientInterceptor``s providing cross-cutting functionality to each
///       accepted RPC. The order in which interceptors are added reflects the order in which they
///       are called. The first interceptor added will be the first interceptor to intercept each
///       request. The last interceptor added will be the final interceptor to intercept each
///       request before calling the appropriate handler.
///   - isolation: A reference to the actor to which the enclosing code is isolated, or nil if the
///       code is nonisolated.
///   - handleClient: A closure which is called with the client. When the closure returns, the
///       client is shutdown gracefully.
public func withGRPCClient<Result: Sendable>(
  transport: some ClientTransport,
  interceptors: [any ClientInterceptor] = [],
  isolation: isolated (any Actor)? = #isolation,
  handleClient: (GRPCClient) async throws -> Result
) async throws -> Result {
  try await withGRPCClient(
    transport: transport,
    interceptorPipeline: interceptors.map { .apply($0, to: .all) },
    isolation: isolation,
    handleClient: handleClient
  )
}

/// Creates and runs a new client with the given transport and interceptors.
///
/// - Parameters:
///   - transport: The transport used to establish a communication channel with a server.
///   - interceptorPipeline: A collection of ``ClientInterceptorPipelineOperation`` providing cross-cutting
///       functionality to each accepted RPC. Only applicable interceptors from the pipeline will be applied to each RPC.
///       The order in which interceptors are added reflects the order in which they are called.
///       The first interceptor added will be the first interceptor to intercept each request.
///       The last interceptor added will be the final interceptor to intercept each request before calling the appropriate handler.
///   - isolation: A reference to the actor to which the enclosing code is isolated, or nil if the
///       code is nonisolated.
///   - handleClient: A closure which is called with the client. When the closure returns, the
///       client is shutdown gracefully.
/// - Returns: The result of the `handleClient` closure.
public func withGRPCClient<Result: Sendable>(
  transport: some ClientTransport,
  interceptorPipeline: [ConditionalInterceptor<any ClientInterceptor>],
  isolation: isolated (any Actor)? = #isolation,
  handleClient: (GRPCClient) async throws -> Result
) async throws -> Result {
  try await withThrowingDiscardingTaskGroup { group in
    let client = GRPCClient(transport: transport, interceptorPipeline: interceptorPipeline)
    group.addTask {
      try await client.run()
    }

    let result = try await handleClient(client)
    client.beginGracefulShutdown()
    return result
  }
}
