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

/// A gRPC client.
///
/// A ``GRPCClient`` communicates to a server via a ``ClientTransport``.
///
/// You can start RPCs to the server by calling the corresponding method:
/// - ``unary(request:descriptor:serializer:deserializer:handler:)``
/// - ``clientStreaming(request:descriptor:serializer:deserializer:handler:)``
/// - ``serverStreaming(request:descriptor:serializer:deserializer:handler:)``
/// - ``bidirectionalStreaming(request:descriptor:serializer:deserializer:handler:)``
///
/// However, in most cases you should prefer wrapping the ``GRPCClient`` with a generated stub.
///
/// You can set ``MethodConfiguration``s on this client to override whatever configurations have been
/// set on the given transport. You can also use ``ClientInterceptor``s to implement cross-cutting
/// logic which apply to all RPCs. Example uses of interceptors include authentication and logging.
///
/// ## Creating and configuring a client
///
/// The following example demonstrates how to create and configure a client.
///
/// ```swift
/// // Create a configuration object for the client.
/// var configuration = GRPCClient.Configuration()
///
/// // Override the timeout for the 'Get' method on the 'echo.Echo' service. This configuration
/// // takes precedence over any set by the transport.
/// let echoGet = MethodDescriptor(service: "echo.Echo", method: "Get")
/// configuration.method.overrides[echoGet] = MethodConfiguration(
///   executionPolicy: nil,
///   timeout: .seconds(5)
/// )
///
/// // Configure a fallback timeout for all RPCs if no configuration is provided in the overrides
/// // or by the transport.
/// let defaultMethodConfiguration = MethodConfiguration(executionPolicy: nil, timeout: seconds(10))
/// configuration.method.defaults.setDefaultConfiguration(defaultMethodConfiguration)
///
/// // Finally create a transport and instantiate the client, adding an interceptor.
/// let inProcessServerTransport = InProcessServerTransport()
/// let inProcessClientTransport = InProcessClientTransport(serverTransport: inProcessServerTransport)
///
/// let client = GRPCClient(
///   transport: inProcessClientTransport,
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
///   client.close()
/// }
/// ```
///
/// The ``run()`` method won't return until the client has finished handling all requests. You can
/// signal to the client that it should stop creating new request streams by calling ``close()``.
/// This gives the client enough time to drain any requests already in flight. To stop the client
/// more abruptly you can cancel the task running your client. If your application requires
/// additional resources that need their lifecycles managed you should consider using [Swift Service
/// Lifecycle](https://github.com/swift-server/swift-service-lifecycle).
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct GRPCClient: Sendable {
  /// The transport which provides a bidirectional communication channel with the server.
  private let transport: any ClientTransport

  /// A collection of interceptors providing cross-cutting functionality to each accepted RPC.
  ///
  /// The order in which interceptors are added reflects the order in which they are called. The
  /// first interceptor added will be the first interceptor to intercept each request. The last
  /// interceptor added will be the final interceptor to intercept each request before calling
  /// the appropriate handler.
  private let interceptors: [any ClientInterceptor]

  /// The configuration used by the client.
  public let configuration: Configuration

  /// The current state of the client.
  private let state: ManagedAtomic<State>

  /// The state of the client.
  private enum State: UInt8, AtomicValue {
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
  ///   - configuration: Configuration for the client.
  public init(
    transport: some ClientTransport,
    interceptors: [any ClientInterceptor] = [],
    configuration: Configuration = Configuration()
  ) {
    self.transport = transport
    self.interceptors = interceptors
    self.configuration = configuration
    self.state = ManagedAtomic(.notStarted)
  }

  /// Start the client.
  ///
  /// This returns once ``close()`` has been called and all in-flight RPCs have finished executing.
  /// If you need to abruptly stop all work you should cancel the task executing this method.
  ///
  /// The client, and by extension this function, can only be run once. If the client is already
  /// running or has already been closed then a ``ClientError`` is thrown.
  public func run() async throws {
    let (wasNotStarted, original) = self.state.compareExchange(
      expected: .notStarted,
      desired: .running,
      ordering: .sequentiallyConsistent
    )

    guard wasNotStarted else {
      switch original {
      case .notStarted:
        // The value wasn't exchanged so the original value can't be 'notStarted'.
        fatalError()
      case .running:
        throw ClientError(
          code: .clientIsAlreadyRunning,
          message: "The client is already running and can only be started once."
        )
      case .stopping, .stopped:
        throw ClientError(
          code: .clientIsStopped,
          message: "The client has stopped and can only be started once."
        )
      }
    }

    // When we exit this function we must have stopped.
    defer {
      self.state.store(.stopped, ordering: .sequentiallyConsistent)
    }

    do {
      try await self.transport.connect(lazily: false)
    } catch {
      throw ClientError(
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
  public func close() {
    while true {
      let (wasRunning, actualState) = self.state.compareExchange(
        expected: .running,
        desired: .stopping,
        ordering: .sequentiallyConsistent
      )

      // Transition from running to stopping: close the transport.
      if wasRunning {
        self.transport.close()
        return
      }

      // The expected state wasn't 'running'. There are two options:
      // 1. The client isn't running yet.
      // 2. The client is already stopping or stopped.
      switch actualState {
      case .notStarted:
        // Not started: try going straight to stopped.
        let (wasNotStarted, _) = self.state.compareExchange(
          expected: .notStarted,
          desired: .stopped,
          ordering: .sequentiallyConsistent
        )

        // If the exchange happened then just return: the client wasn't started so there's no
        // transport to start.
        //
        // If the exchange didn't happen then continue looping: the client must've been started by
        // another thread.
        if wasNotStarted {
          return
        } else {
          continue
        }

      case .running:
        // Unreachable: the value was exchanged and this was the expected value.
        fatalError()

      case .stopping, .stopped:
        // No exchange happened but the client is already stopping.
        return
      }
    }
  }

  /// Executes a unary RPC.
  ///
  /// - Parameters:
  ///   - request: The unary request.
  ///   - descriptor: The method descriptor for which to execute this request.
  ///   - serializer: A request serializer.
  ///   - deserializer: A response deserializer.
  ///   - handler: A unary response handler.
  ///
  /// - Returns: The return value from the `handler`.
  public func unary<Request, Response, ReturnValue>(
    request: ClientRequest.Single<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    handler: @Sendable @escaping (ClientResponse.Single<Response>) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    try await self.bidirectionalStreaming(
      request: ClientRequest.Stream(single: request),
      descriptor: descriptor,
      serializer: serializer,
      deserializer: deserializer
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
  ///   - handler: A unary response handler.
  ///
  /// - Returns: The return value from the `handler`.
  public func clientStreaming<Request, Response, ReturnValue>(
    request: ClientRequest.Stream<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    handler: @Sendable @escaping (ClientResponse.Single<Response>) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    try await self.bidirectionalStreaming(
      request: request,
      descriptor: descriptor,
      serializer: serializer,
      deserializer: deserializer
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
  ///   - handler: A response stream handler.
  ///
  /// - Returns: The return value from the `handler`.
  public func serverStreaming<Request, Response, ReturnValue>(
    request: ClientRequest.Single<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    handler: @Sendable @escaping (ClientResponse.Stream<Response>) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    try await self.bidirectionalStreaming(
      request: ClientRequest.Stream(single: request),
      descriptor: descriptor,
      serializer: serializer,
      deserializer: deserializer,
      handler: handler
    )
  }

  /// Start a bidirectional streaming RPC.
  ///
  /// - Note: ``run()`` must have been called and still executing, and ``close()`` mustn't
  /// have been called.
  ///
  /// - Parameters:
  ///   - request: The streaming request.
  ///   - descriptor: The method descriptor for which to execute this request.
  ///   - serializer: A request serializer.
  ///   - deserializer: A response deserializer.
  ///   - handler: A response stream handler.
  ///
  /// - Returns: The return value from the `handler`.
  public func bidirectionalStreaming<Request, Response, ReturnValue>(
    request: ClientRequest.Stream<Request>,
    descriptor: MethodDescriptor,
    serializer: some MessageSerializer<Request>,
    deserializer: some MessageDeserializer<Response>,
    handler: @Sendable @escaping (ClientResponse.Stream<Response>) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    switch self.state.load(ordering: .sequentiallyConsistent) {
    case .notStarted, .running:
      // Allow .notStarted as making a request can race with 'run()'. Transports should tolerate
      // queuing the request if not yet started.
      ()
    case .stopping, .stopped:
      throw ClientError(
        code: .clientIsStopped,
        message: "Client has been stopped. Can't make any more RPCs."
      )
    }

    return try await ClientRPCExecutor.execute(
      request: request,
      method: descriptor,
      configuration: self.resolveMethodConfiguration(for: descriptor),
      serializer: serializer,
      deserializer: deserializer,
      transport: self.transport,
      interceptors: self.interceptors,
      handler: handler
    )
  }

  private func resolveMethodConfiguration(for descriptor: MethodDescriptor) -> MethodConfiguration {
    if let configuration = self.configuration.method.overrides[descriptor] {
      return configuration
    }

    if let configuration = self.transport.executionConfiguration(forMethod: descriptor) {
      return configuration
    }

    if let configuration = self.configuration.method.defaults[descriptor] {
      return configuration
    }

    // No configuration found, return the "vanilla" configuration.
    return MethodConfiguration(names: [], timeout: nil, executionPolicy: nil)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCClient {
  public struct Configuration: Sendable {
    /// Configuration for how methods are executed.
    ///
    /// Method configuration determines how each RPC is executed by the client. Some services and
    /// transports provide this information to the client when the server name is resolved. However,
    /// you override this configuration and set default values should no override be set and the
    /// transport doesn't provide a value.
    public var method: Method

    /// Creates a new default configuration.
    public init() {
      self.method = Method()
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCClient.Configuration {
  /// Configuration for how methods should be executed.
  ///
  /// In most cases the client should defer to the configuration provided by the transport as this
  /// can be provided to the transport as part of name resolution when establishing a connection.
  ///
  /// The client first checks ``overrides`` for a configuration, followed by the transport, followed
  /// by ``defaults``.
  public struct Method: Sendable, Hashable {
    /// Configuration to use in precedence to that provided by the transport.
    public var overrides: MethodConfigurations

    /// Configuration to use only if there are no overrides and the transport doesn't specify
    /// any configuration.
    public var defaults: MethodConfigurations

    public init() {
      self.overrides = MethodConfigurations()
      self.defaults = MethodConfigurations()
    }
  }
}
