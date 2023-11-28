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

/// A gRPC client.
///
/// A ``GRPCClient`` communicates to a server via a given ``ClientTransport``.
/// You can start RPCs to the server by calling the corresponding method:
/// - ``unary(request:descriptor:serializer:deserializer:handler:)``
/// - ``clientStreaming(request:descriptor:serializer:deserializer:handler:)``
/// - ``serverStreaming(request:descriptor:serializer:deserializer:handler:)``
/// - ``bidirectionalStreaming(request:descriptor:serializer:deserializer:handler:)``
///
/// You can set ``MethodConfiguration``s on this client to override whatever configurations have been
/// set on the given transport.
/// You can also use ``ClientInterceptor``s to implement cross-cutting logic which apply to all
/// RPCs. Example uses of interceptors include authentication and logging.
///
/// ## Creating and configuring a client
///
/// The following example demonstrates how to create and configure a server.
///
/// ```swift
/// // Create and add an in-process transport.
/// let inProcessTransport = InProcessClientTransport()
/// let client = GRPCClient(transport: inProcessTransport)
///
/// // Create and add some interceptors.
/// client.interceptors.add(StatsRecordingServerInterceptors())
///
/// // Create and add some method configurations.
/// let defaultConfiguration = MethodConfiguration(
///     executionPolicy: ...,
///     timeout: ...
/// )
/// let registry = MethodConfigurationRegistry(defaultConfiguration: defaultConfiguration)
/// client.methodConfigurationOverrides = registry
/// ```
///
/// ## Starting and stopping the client
///
/// Once you have configured the client, call ``run()`` to start it. Calling ``run()`` connects to the given
/// transport.
///
/// ```swift
/// // Start running the client.
/// try await client.run()
/// ```
///
/// The ``run()`` method won't return until the client has finished handling all requests. You can
/// signal to the client that it should stop creating new request streams by calling ``close()``.
/// This gives the client enough time to drain any requests already in flight. To stop the client more abruptly
/// you can cancel the task running your client. If your application requires additional resources
/// that need their lifecycles managed you should consider using [Swift Service
/// Lifecycle](https://github.com/swift-server/swift-service-lifecycle).
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public final class GRPCClient: Sendable {
  /// A collection of ``ClientInterceptor`` implementations which are applied to all accepted
  /// RPCs.
  ///
  /// RPCs are intercepted in the order that interceptors are added. That is, a request sent from the client to
  /// the server will first be intercepted by the first added interceptor followed by the second, and so on.
  /// For responses from the server, they'll be applied in the opposite order.
  public var interceptors: Interceptors {
    get {
      self.storage.withLockedValue { $0.interceptors }
    }
    set {
      self.storage.withLockedValue { storage in
        if case .notStarted = storage.state {
          storage.interceptors = newValue
        }
      }
    }
  }

  /// A ``MethodConfigurationRegistry`` containing ``MethodConfiguration``s for calls
  /// made from this ``Client``.
  ///
  /// - Note: These configurations will override those configurations set in the ``ClientTransport``.
  public var methodConfigurationOverrides: MethodConfigurationRegistry {
    get {
      self.storage.withLockedValue { $0.methodConfigurationOverrides }
    }
    set {
      self.storage.withLockedValue { storage in
        if case .notStarted = storage.state {
          storage.methodConfigurationOverrides = newValue
        }
      }
    }
  }

  /// The state of the client.
  private enum State {
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

  /// Underlying storage for the client.
  private struct Storage {
    var interceptors: Interceptors
    var methodConfigurationOverrides: MethodConfigurationRegistry
    var state: State

    init() {
      self.interceptors = Interceptors()
      self.methodConfigurationOverrides = MethodConfigurationRegistry()
      self.state = .notStarted
    }
  }

  private let storage: LockedValueBox<Storage>

  /// The transport which provides a bidirectional communication channel with the server.
  private let transport: ClientTransport

  /// Creates a new client with no resources.
  ///
  /// You can add resources to the client via ``interceptors-swift.property`` and
  /// ``methodConfigurationOverrides-swift.property``, and start the client by calling ``run()``.
  ///
  /// - Note: Any changes to resources after ``run()`` has been called will be ignored.
  ///
  /// - Parameter transport: The ``ClientTransport`` to be used for this ``GRPCClient``.
  public init(transport: ClientTransport) {
    self.storage = LockedValueBox(Storage())
    self.transport = transport
  }

  /// Start the client.
  ///
  /// This is a long-running task that will return once ``close()`` has been called and all in-flight RPCs
  /// finished executing.
  ///
  /// If you need to immediately stop all work, cancel the task executing this method.
  public func run() async throws {
    try self.storage.withLockedValue { storage in
      switch storage.state {
      case .notStarted:
        storage.state = .running
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
      self.storage.withLockedValue { $0.state = .stopped }
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await self.transport.connect(lazily: false)
      }
      try await group.next()
    }
  }

  /// Close the client.
  ///
  /// The transport will be closed: this means that it will be given enough time to wait for in-flight RPCs to
  /// finish executing, but no new RPCs will be accepted.
  /// You can cancel the task executing ``run()`` if you want to immediately stop all work.
  public func close() {
    self.storage.withLockedValue { storage in
      switch storage.state {
      case .notStarted:
        storage.state = .stopped
      case .running:
        storage.state = .stopping
      case .stopping, .stopped:
        ()
      }
    }

    self.transport.close()
  }

  /// Start a unary RPC.
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
    let (configurationOverrides, interceptors) = try self.storage.withLockedValue { storage in
      switch storage.state {
      case .running:
        return (storage.methodConfigurationOverrides, storage.interceptors.values)
      case .notStarted:
        throw ClientError(
          code: .clientIsNotRunning,
          message: "Client must be running to make an RPC: call run() first."
        )
      case .stopping, .stopped:
        throw ClientError(
          code: .clientIsStopped,
          message: "Client has been stopped. Can't make any more RPCs."
        )
      }
    }

    let applicableConfiguration = self.resolveMethodConfiguration(
      descriptor: descriptor,
      clientConfigurations: configurationOverrides
    )

    return try await ClientRPCExecutor.execute(
      request: ClientRequest.Stream(single: request),
      method: descriptor,
      configuration: applicableConfiguration,
      serializer: serializer,
      deserializer: deserializer,
      transport: self.transport,
      interceptors: interceptors,
      handler: { stream in
        let singleResponse = await ClientResponse.Single(stream: stream)
        return try await handler(singleResponse)
      }
    )
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
    let (configurationOverrides, interceptors) = try self.storage.withLockedValue { storage in
      switch storage.state {
      case .running:
        return (storage.methodConfigurationOverrides, storage.interceptors.values)
      case .notStarted:
        throw ClientError(
          code: .clientIsNotRunning,
          message: "Client must be running to make an RPC: call run() first."
        )
      case .stopping, .stopped:
        throw ClientError(
          code: .clientIsStopped,
          message: "Client has been stopped. Can't make any more RPCs."
        )
      }
    }

    let applicableConfiguration = self.resolveMethodConfiguration(
      descriptor: descriptor,
      clientConfigurations: configurationOverrides
    )

    return try await ClientRPCExecutor.execute(
      request: request,
      method: descriptor,
      configuration: applicableConfiguration,
      serializer: serializer,
      deserializer: deserializer,
      transport: transport,
      interceptors: interceptors,
      handler: { stream in
        let singleResponse = await ClientResponse.Single(stream: stream)
        return try await handler(singleResponse)
      }
    )
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
    let (configurationOverrides, interceptors) = try self.storage.withLockedValue { storage in
      switch storage.state {
      case .running:
        return (storage.methodConfigurationOverrides, storage.interceptors.values)
      case .notStarted:
        throw ClientError(
          code: .clientIsNotRunning,
          message: "Client must be running to make an RPC: call run() first."
        )
      case .stopping, .stopped:
        throw ClientError(
          code: .clientIsStopped,
          message: "Client has been stopped. Can't make any more RPCs."
        )
      }
    }

    let applicableConfiguration = self.resolveMethodConfiguration(
      descriptor: descriptor,
      clientConfigurations: configurationOverrides
    )

    return try await ClientRPCExecutor.execute(
      request: ClientRequest.Stream(single: request),
      method: descriptor,
      configuration: applicableConfiguration,
      serializer: serializer,
      deserializer: deserializer,
      transport: transport,
      interceptors: interceptors,
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
    let (configurationOverrides, interceptors) = try self.storage.withLockedValue { storage in
      switch storage.state {
      case .running:
        return (storage.methodConfigurationOverrides, storage.interceptors.values)
      case .notStarted:
        throw ClientError(
          code: .clientIsNotRunning,
          message: "Client must be running to make an RPC: call run() first."
        )
      case .stopping, .stopped:
        throw ClientError(
          code: .clientIsStopped,
          message: "Client has been stopped. Can't make any more RPCs."
        )
      }
    }

    let applicableConfiguration = self.resolveMethodConfiguration(
      descriptor: descriptor,
      clientConfigurations: configurationOverrides
    )

    return try await ClientRPCExecutor.execute(
      request: request,
      method: descriptor,
      configuration: applicableConfiguration,
      serializer: serializer,
      deserializer: deserializer,
      transport: transport,
      interceptors: interceptors,
      handler: handler
    )
  }

  private func resolveMethodConfiguration(
    descriptor: MethodDescriptor,
    clientConfigurations configurationOverrides: MethodConfigurationRegistry
  ) -> MethodConfiguration {
    if let clientOverride = configurationOverrides[descriptor, useDefault: false] {
      return clientOverride
    }

    if let transportConfiguration = self.transport.executionConfiguration(forMethod: descriptor) {
      return transportConfiguration
    }

    return configurationOverrides[descriptor]
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCClient {
  /// A collection of interceptors providing cross-cutting functionality to each accepted RPC.
  public struct Interceptors: Sendable {
    private(set) var values: [any ClientInterceptor] = []

    /// Add an interceptor to the server.
    ///
    /// The order in which interceptors are added reflects the order in which they are called. The
    /// first interceptor added will be the first interceptor to intercept each request. The last
    /// interceptor added will be the final interceptor to intercept each request before calling
    /// the appropriate handler.
    ///
    /// - Parameter interceptor: The interceptor to add.
    public mutating func add(_ interceptor: some ClientInterceptor) {
      self.values.append(interceptor)
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCClient {
  /// The execution policy for an RPC.
  public enum ExecutionPolicy: Hashable, Sendable {
    /// Policy for retrying an RPC.
    ///
    /// See ``RetryPolicy`` for more details.
    case retry(MethodConfiguration.RetryPolicy)

    /// Policy for hedging an RPC.
    ///
    /// See ``HedgingPolicy`` for more details.
    case hedge(MethodConfiguration.HedgingPolicy)
  }

  /// Configuration values for executing an RPC.
  public struct MethodConfiguration: Hashable, Sendable {
    /// The default timeout for the RPC.
    ///
    /// If no reply is received in the specified amount of time the request is aborted
    /// with an ``RPCError`` with code ``RPCError/Code/deadlineExceeded``.
    ///
    /// The actual deadline used will be the minimum of the value specified here
    /// and the value set by the application by the client API. If either one isn't set
    /// then the other value is used. If neither is set then the request has no deadline.
    ///
    /// The timeout applies to the overall execution of an RPC. If, for example, a retry
    /// policy is set then the timeout begins when the first attempt is started and _isn't_ reset
    /// when subsequent attempts start.
    public var timeout: Duration?

    /// The policy determining how many times, and when, the RPC is executed.
    ///
    /// There are two policy types:
    /// 1. Retry
    /// 2. Hedging
    ///
    /// The retry policy allows an RPC to be retried a limited number of times if the RPC
    /// fails with one of the configured set of status codes. RPCs are only retried if they
    /// fail immediately, that is, the first response part received from the server is a
    /// status code.
    ///
    /// The hedging policy allows an RPC to be executed multiple times concurrently. Typically
    /// each execution will be staggered by some delay. The first successful response will be
    /// reported to the client. Hedging is only suitable for idempotent RPCs.
    public var executionPolicy: ExecutionPolicy?

    /// Create an execution configuration.
    ///
    /// - Parameters:
    ///   - executionPolicy: The execution policy to use for the RPC.
    ///   - timeout: The default timeout for the RPC.
    public init(
      executionPolicy: ExecutionPolicy?,
      timeout: Duration?
    ) {
      self.executionPolicy = executionPolicy
      self.timeout = timeout
    }

    /// Create an execution configuration with a retry policy.
    ///
    /// - Parameters:
    ///   - retryPolicy: The policy for retrying the RPC.
    ///   - timeout: The default timeout for the RPC.
    public init(
      retryPolicy: RetryPolicy,
      timeout: Duration? = nil
    ) {
      self.executionPolicy = .retry(retryPolicy)
      self.timeout = timeout
    }

    /// Create an execution configuration with a hedging policy.
    ///
    /// - Parameters:
    ///   - hedgingPolicy: The policy for hedging the RPC.
    ///   - timeout: The default timeout for the RPC.
    public init(
      hedgingPolicy: HedgingPolicy,
      timeout: Duration? = nil
    ) {
      self.executionPolicy = .hedge(hedgingPolicy)
      self.timeout = timeout
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCClient.MethodConfiguration {
  /// Policy for retrying an RPC.
  ///
  /// gRPC retries RPCs when the first response from the server is a status code which matches
  /// one of the configured retryable status codes. If the server begins processing the RPC and
  /// first responds with metadata and later responds with a retryable status code then the RPC
  /// won't be retried.
  ///
  /// Execution attempts are limited by ``maximumAttempts`` which includes the original attempt. The
  /// maximum number of attempts is limited to five.
  ///
  /// Subsequent attempts are executed after some delay. The first _retry_, or second attempt, will
  /// be started after a randomly chosen delay between zero and ``initialBackoff``. More generally,
  /// the nth retry will happen after a randomly chosen delay between zero
  /// and `min(initialBackoff * backoffMultiplier^(n-1), maximumBackoff)`.
  ///
  /// For more information see [gRFC A6 Client
  /// Retries](https://github.com/grpc/proposal/blob/master/A6-client-retries.md).
  public struct RetryPolicy: Hashable, Sendable {
    /// The maximum number of RPC attempts, including the original attempt.
    ///
    /// Must be greater than one, values greater than five are treated as five.
    public var maximumAttempts: Int {
      didSet { self.maximumAttempts = validateMaxAttempts(self.maximumAttempts) }
    }

    /// The initial backoff duration.
    ///
    /// The initial retry will occur after a random amount of time up to this value.
    ///
    /// - Precondition: Must be greater than zero.
    public var initialBackoff: Duration {
      willSet { Self.validateInitialBackoff(newValue) }
    }

    /// The maximum amount of time to backoff for.
    ///
    /// - Precondition: Must be greater than zero.
    public var maximumBackoff: Duration {
      willSet { Self.validateMaxBackoff(newValue) }
    }

    /// The multiplier to apply to backoff.
    ///
    /// - Precondition: Must be greater than zero.
    public var backoffMultiplier: Double {
      willSet { Self.validateBackoffMultiplier(newValue) }
    }

    /// The set of status codes which may be retried.
    ///
    /// - Precondition: Must not be empty.
    public var retryableStatusCodes: Set<Status.Code> {
      willSet { Self.validateRetryableStatusCodes(newValue) }
    }

    /// Create a new retry policy.
    ///
    /// - Parameters:
    ///   - maximumAttempts: The maximum number of attempts allowed for the RPC.
    ///   - initialBackoff: The initial backoff period for the first retry attempt. Must be
    ///       greater than zero.
    ///   - maximumBackoff: The maximum period of time to wait between attempts. Must be greater than
    ///       zero.
    ///   - backoffMultiplier: The exponential backoff multiplier. Must be greater than zero.
    ///   - retryableStatusCodes: The set of status codes which may be retried. Must not be empty.
    /// - Precondition: `maximumAttempts`, `initialBackoff`, `maximumBackoff` and `backoffMultiplier`
    ///     must be greater than zero.
    /// - Precondition: `retryableStatusCodes` must not be empty.
    public init(
      maximumAttempts: Int,
      initialBackoff: Duration,
      maximumBackoff: Duration,
      backoffMultiplier: Double,
      retryableStatusCodes: Set<Status.Code>
    ) {
      self.maximumAttempts = validateMaxAttempts(maximumAttempts)

      Self.validateInitialBackoff(initialBackoff)
      self.initialBackoff = initialBackoff

      Self.validateMaxBackoff(maximumBackoff)
      self.maximumBackoff = maximumBackoff

      Self.validateBackoffMultiplier(backoffMultiplier)
      self.backoffMultiplier = backoffMultiplier

      Self.validateRetryableStatusCodes(retryableStatusCodes)
      self.retryableStatusCodes = retryableStatusCodes
    }

    private static func validateInitialBackoff(_ value: Duration) {
      precondition(value.isGreaterThanZero, "initialBackoff must be greater than zero")
    }

    private static func validateMaxBackoff(_ value: Duration) {
      precondition(value.isGreaterThanZero, "maximumBackoff must be greater than zero")
    }

    private static func validateBackoffMultiplier(_ value: Double) {
      precondition(value > 0, "backoffMultiplier must be greater than zero")
    }

    private static func validateRetryableStatusCodes(_ value: Set<Status.Code>) {
      precondition(!value.isEmpty, "retryableStatusCodes mustn't be empty")
    }
  }

  /// Policy for hedging an RPC.
  ///
  /// Hedged RPCs may execute more than once on a server so only idempotent methods should
  /// be hedged.
  ///
  /// gRPC executes the RPC at most ``maximumAttempts`` times, staggering each attempt
  /// by ``hedgingDelay``.
  ///
  /// For more information see [gRFC A6 Client
  /// Retries](https://github.com/grpc/proposal/blob/master/A6-client-retries.md).
  public struct HedgingPolicy: Hashable, Sendable {
    /// The maximum number of RPC attempts, including the original attempt.
    ///
    /// Values greater than five are treated as five.
    ///
    /// - Precondition: Must be greater than one.
    public var maximumAttempts: Int {
      didSet { self.maximumAttempts = validateMaxAttempts(self.maximumAttempts) }
    }

    /// The first RPC will be sent immediately, but each subsequent RPC will be sent at intervals
    /// of `hedgingDelay`. Set this to zero to immediately send all RPCs.
    public var hedgingDelay: Duration {
      willSet { Self.validateHedgingDelay(newValue) }
    }

    /// The set of status codes which indicate other hedged RPCs may still succeed.
    ///
    /// If a non-fatal status code is returned by the server, hedged RPCs will continue.
    /// Otherwise, outstanding requests will be cancelled and the error returned to the
    /// application layer.
    public var nonFatalStatusCodes: Set<Status.Code>

    /// Create a new hedging policy.
    ///
    /// - Parameters:
    ///   - maximumAttempts: The maximum number of attempts allowed for the RPC.
    ///   - hedgingDelay: The delay between each hedged RPC.
    ///   - nonFatalStatusCodes: The set of status codes which indicated other hedged RPCs may still
    ///       succeed.
    /// - Precondition: `maximumAttempts` must be greater than zero.
    public init(
      maximumAttempts: Int,
      hedgingDelay: Duration,
      nonFatalStatusCodes: Set<Status.Code>
    ) {
      self.maximumAttempts = validateMaxAttempts(maximumAttempts)

      Self.validateHedgingDelay(hedgingDelay)
      self.hedgingDelay = hedgingDelay
      self.nonFatalStatusCodes = nonFatalStatusCodes
    }

    private static func validateHedgingDelay(_ value: Duration) {
      precondition(
        value.isGreaterThanOrEqualToZero,
        "hedgingDelay must be greater than or equal to zero"
      )
    }
  }

  fileprivate static func validateMaxAttempts(_ value: Int) -> Int {
    precondition(value > 0, "maximumAttempts must be greater than zero")
    return min(value, 5)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCClient {
  /// A collection of ``ClientRPCExecutionConfiguration``s, mapped to specific methods or services.
  ///
  /// When creating a new instance, you must provide a default configuration to be used when getting
  /// a configuration for a method that has not been given a specific override.
  /// Use ``setDefaultConfiguration(_:forService:)`` to set a specific override for a whole
  /// service.
  ///
  /// Use the subscript to get and set configurations for methods.
  public struct MethodConfigurationRegistry: Sendable, Hashable {
    private var elements: [MethodDescriptor: MethodConfiguration]
    private let defaultConfiguration: MethodConfiguration

    public init(
      defaultConfiguration: MethodConfiguration = MethodConfiguration(
        executionPolicy: nil,
        timeout: nil
      )
    ) {
      self.elements = [:]
      self.defaultConfiguration = defaultConfiguration
    }

    /// Get the corresponding ``MethodConfiguration`` for the given ``MethodDescriptor``.
    ///
    /// If `useDefault` is true, then fall back to the default configuration given in ``init(defaultConfiguration:)``
    /// if there is no set configuration for the descriptor. Otherwise, return `nil`.
    ///
    /// - Parameters:
    ///  - descriptor: The ``MethodDescriptor`` for which to get a ``MethodConfiguration``.
    ///  - useDefault: Whether the default value should be returned if no configuration was specified
    ///  for the given descriptor.
    public subscript(_ descriptor: MethodDescriptor, useDefault useDefault: Bool)
      -> MethodConfiguration?
    {
      get {
        if let methodLevelOverride = self.elements[descriptor] {
          return methodLevelOverride
        }
        var serviceLevelDescriptor = descriptor
        serviceLevelDescriptor.method = ""

        if useDefault {
          return self.elements[serviceLevelDescriptor, default: self.defaultConfiguration]
        } else {
          return self.elements[serviceLevelDescriptor]
        }
      }
    }

    /// Get or set the corresponding ``MethodConfiguration`` for the given ``MethodDescriptor``.
    ///
    /// If no configuration has been set for the given descriptor, the value returned will be the default
    /// passed in ``init(defaultConfiguration:)``
    ///
    /// - Parameters:
    ///  - descriptor: The ``MethodDescriptor`` for which to get or set a ``MethodConfiguration``.
    public subscript(_ descriptor: MethodDescriptor) -> MethodConfiguration {
      get {
        // This force unwrap is safe, because we'll always have a default value
        // present, and we'll always use it if `useDefault` is true.
        self[descriptor, useDefault: true]!
      }

      set {
        precondition(
          !descriptor.service.isEmpty,
          "Method descriptor's service cannot be empty."
        )

        self.elements[descriptor] = newValue
      }
    }

    /// Set a default configuration for a service.
    ///
    /// If getting a configuration for a method that's part of a service, and the method itself doesn't have an
    /// override, then this configuration will be used instead of the default configuration passed when creating
    /// this instance of ``ClientRPCExecutionConfigurationCollection``.
    ///
    /// - Parameters:
    ///   - configuration: The default configuration for the service.
    ///   - service: The name of the service for which this override applies.
    public mutating func setDefaultConfiguration(
      _ configuration: MethodConfiguration,
      forService service: String
    ) {
      self[MethodDescriptor(service: service, method: "")] = configuration
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Duration {
  fileprivate var isGreaterThanZero: Bool {
    self.components.seconds > 0 || self.components.attoseconds > 0
  }

  fileprivate var isGreaterThanOrEqualToZero: Bool {
    self.components.seconds >= 0 || self.components.attoseconds >= 0
  }
}
