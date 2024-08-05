/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

internal import Atomics
internal import DequeModule
package import GRPCCore

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
package struct GRPCChannel: ClientTransport {
  private enum Input: Sendable {
    /// Close the channel, if possible.
    case close
    /// Handle the result of a name resolution.
    case handleResolutionResult(NameResolutionResult)
    /// Handle the event from the underlying connection object.
    case handleLoadBalancerEvent(LoadBalancerEvent, LoadBalancerID)
  }

  /// Events which can happen to the channel.
  private let _connectivityState:
    (
      stream: AsyncStream<ConnectivityState>,
      continuation: AsyncStream<ConnectivityState>.Continuation
    )

  /// Inputs which this channel should react to.
  private let input: (stream: AsyncStream<Input>, continuation: AsyncStream<Input>.Continuation)

  /// A resolver providing resolved names to the channel.
  private let resolver: NameResolver

  /// The state of the channel.
  private let state: LockedValueBox<StateMachine>

  /// The maximum number of times to attempt to create a stream per RPC.
  ///
  /// This is the value used by other gRPC implementations.
  private static let maxStreamCreationAttempts = 5

  /// A factory for connections.
  private let connector: any HTTP2Connector

  /// The connection backoff configuration used by the subchannel when establishing a connection.
  private let backoff: ConnectionBackoff

  /// The default compression algorithm used for requests.
  private let defaultCompression: CompressionAlgorithm

  /// The set of enabled compression algorithms.
  private let enabledCompression: CompressionAlgorithmSet

  /// The default service config to use.
  ///
  /// Used when the resolver doesn't provide one.
  private let defaultServiceConfig: ServiceConfig

  // These are both read frequently and updated infrequently so may be a bottleneck.
  private let _methodConfig: LockedValueBox<MethodConfigs>
  private let _retryThrottle: LockedValueBox<RetryThrottle?>

  package init(
    resolver: NameResolver,
    connector: any HTTP2Connector,
    config: Config,
    defaultServiceConfig: ServiceConfig
  ) {
    self.resolver = resolver
    self.state = LockedValueBox(StateMachine())
    self._connectivityState = AsyncStream.makeStream()
    self.input = AsyncStream.makeStream()
    self.connector = connector

    self.backoff = ConnectionBackoff(
      initial: config.backoff.initial,
      max: config.backoff.max,
      multiplier: config.backoff.multiplier,
      jitter: config.backoff.jitter
    )
    self.defaultCompression = config.compression.algorithm
    self.enabledCompression = config.compression.enabledAlgorithms
    self.defaultServiceConfig = defaultServiceConfig

    let throttle = defaultServiceConfig.retryThrottling.map { RetryThrottle(policy: $0) }
    self._retryThrottle = LockedValueBox(throttle)

    let methodConfig = MethodConfigs(serviceConfig: defaultServiceConfig)
    self._methodConfig = LockedValueBox(methodConfig)
  }

  /// The connectivity state of the channel.
  package var connectivityState: AsyncStream<ConnectivityState> {
    self._connectivityState.stream
  }

  /// Returns a throttle which gRPC uses to determine whether retries can be executed.
  package var retryThrottle: RetryThrottle? {
    self._retryThrottle.withLockedValue { $0 }
  }

  /// Returns the configuration for a given method.
  ///
  /// - Parameter descriptor: The method to lookup configuration for.
  /// - Returns: Configuration for the method, if it exists.
  package func configuration(forMethod descriptor: MethodDescriptor) -> MethodConfig? {
    self._methodConfig.withLockedValue { $0[descriptor] }
  }

  /// Establishes and maintains a connection to the remote destination.
  package func connect() async {
    self.state.withLockedValue { $0.start() }
    self._connectivityState.continuation.yield(.idle)

    await withDiscardingTaskGroup { group in
      var iterator: Optional<RPCAsyncSequence<NameResolutionResult, any Error>.AsyncIterator>

      // The resolver can either push or pull values. If it pushes values the channel should
      // listen for new results. Otherwise the channel will pull values as and when necessary.
      switch self.resolver.updateMode.value {
      case .push:
        iterator = nil

        let handle = group.addCancellableTask {
          do {
            for try await result in self.resolver.names {
              self.input.continuation.yield(.handleResolutionResult(result))
            }
            self.close()
          } catch {
            self.close()
          }
        }

        // When the channel is closed gracefully, the task group running the load balancer mustn't
        // be cancelled (otherwise in-flight RPCs would fail), but the push based resolver will
        // continue indefinitely. Store its handle and cancel it on close when closing the channel.
        self.state.withLockedValue { state in
          state.setNameResolverTaskHandle(handle)
        }

      case .pull:
        iterator = self.resolver.names.makeAsyncIterator()
        await self.resolve(iterator: &iterator, in: &group)
      }

      // Resolver is setup, start handling events.
      for await input in self.input.stream {
        switch input {
        case .close:
          self.handleClose(in: &group)

        case .handleResolutionResult(let result):
          self.handleNameResolutionResult(result, in: &group)

        case .handleLoadBalancerEvent(let event, let id):
          await self.handleLoadBalancerEvent(
            event,
            loadBalancerID: id,
            in: &group,
            iterator: &iterator
          )
        }
      }
    }

    if Task.isCancelled {
      self._connectivityState.continuation.finish()
    }
  }

  /// Signal to the transport that no new streams may be created and that connections should be
  /// closed when all streams are closed.
  package func close() {
    self.input.continuation.yield(.close)
  }

  /// Opens a stream using the transport, and uses it as input into a user-provided closure.
  package func withStream<T: Sendable>(
    descriptor: MethodDescriptor,
    options: CallOptions,
    _ closure: (_ stream: RPCStream<Inbound, Outbound>) async throws -> T
  ) async throws -> T {
    // Merge options from the call with those from the service config.
    let methodConfig = self.configuration(forMethod: descriptor)
    var options = options
    options.formUnion(with: methodConfig)

    for attempt in 1 ... Self.maxStreamCreationAttempts {
      switch await self.makeStream(descriptor: descriptor, options: options) {
      case .created(let stream):
        return try await stream.execute { inbound, outbound in
          let rpcStream = RPCStream(
            descriptor: stream.descriptor,
            inbound: RPCAsyncSequence<RPCResponsePart, any Error>(wrapping: inbound),
            outbound: RPCWriter.Closable(wrapping: outbound)
          )
          return try await closure(rpcStream)
        }

      case .tryAgain(let error):
        if error is CancellationError || attempt == Self.maxStreamCreationAttempts {
          throw error
        } else {
          continue
        }

      case .stopTrying(let error):
        throw error
      }
    }

    fatalError("Internal inconsistency")
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension GRPCChannel {
  package struct Config: Sendable {
    /// Configuration for HTTP/2 connections.
    package var http2: HTTP2ClientTransport.Config.HTTP2

    /// Configuration for backoff used when establishing a connection.
    package var backoff: HTTP2ClientTransport.Config.Backoff

    /// Configuration for connection management.
    package var connection: HTTP2ClientTransport.Config.Connection

    /// Compression configuration.
    package var compression: HTTP2ClientTransport.Config.Compression

    package init(
      http2: HTTP2ClientTransport.Config.HTTP2,
      backoff: HTTP2ClientTransport.Config.Backoff,
      connection: HTTP2ClientTransport.Config.Connection,
      compression: HTTP2ClientTransport.Config.Compression
    ) {
      self.http2 = http2
      self.backoff = backoff
      self.connection = connection
      self.compression = compression
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension GRPCChannel {
  enum MakeStreamResult {
    /// A stream was created, use it.
    case created(Connection.Stream)
    /// An error occurred while trying to create a stream, try again if possible.
    case tryAgain(any Error)
    /// An unrecoverable error occurred (e.g. the channel is closed), fail the RPC and don't retry.
    case stopTrying(any Error)
  }

  private func makeStream(
    descriptor: MethodDescriptor,
    options: CallOptions
  ) async -> MakeStreamResult {
    let waitForReady = options.waitForReady ?? true
    switch self.state.withLockedValue({ $0.makeStream(waitForReady: waitForReady) }) {
    case .useLoadBalancer(let loadBalancer):
      return await self.makeStream(
        descriptor: descriptor,
        options: options,
        loadBalancer: loadBalancer
      )

    case .joinQueue:
      do {
        let loadBalancer = try await self.enqueue(waitForReady: waitForReady)
        return await self.makeStream(
          descriptor: descriptor,
          options: options,
          loadBalancer: loadBalancer
        )
      } catch {
        // All errors from enqueue are non-recoverable: either the channel is shutting down or
        // the request has been cancelled.
        return .stopTrying(error)
      }

    case .failRPC:
      return .stopTrying(RPCError(code: .unavailable, message: "channel isn't ready"))
    }
  }

  private func makeStream(
    descriptor: MethodDescriptor,
    options: CallOptions,
    loadBalancer: LoadBalancer
  ) async -> MakeStreamResult {
    guard let subchannel = loadBalancer.pickSubchannel() else {
      return .tryAgain(RPCError(code: .unavailable, message: "channel isn't ready"))
    }

    let methodConfig = self.configuration(forMethod: descriptor)
    var options = options
    options.formUnion(with: methodConfig)

    do {
      let stream = try await subchannel.makeStream(descriptor: descriptor, options: options)
      return .created(stream)
    } catch {
      return .tryAgain(error)
    }
  }

  private func enqueue(waitForReady: Bool) async throws -> LoadBalancer {
    let id = QueueEntryID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
          return
        }

        let enqueued = self.state.withLockedValue { state in
          state.enqueue(continuation: continuation, waitForReady: waitForReady, id: id)
        }

        // Not enqueued because the channel is shutdown or shutting down.
        if !enqueued {
          let error = RPCError(code: .unavailable, message: "channel is shutdown")
          continuation.resume(throwing: error)
        }
      }
    } onCancel: {
      let continuation = self.state.withLockedValue { state in
        state.dequeueContinuation(id: id)
      }

      continuation?.resume(throwing: CancellationError())
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension GRPCChannel {
  private func handleClose(in group: inout DiscardingTaskGroup) {
    switch self.state.withLockedValue({ $0.close() }) {
    case .close(let current, let next, let resolver, let continuations):
      resolver?.cancel()
      current.close()
      next?.close()
      for continuation in continuations {
        continuation.resume(throwing: RPCError(code: .unavailable, message: "channel is closed"))
      }
      self._connectivityState.continuation.yield(.shutdown)

    case .cancelAll(let continuations):
      for continuation in continuations {
        continuation.resume(throwing: RPCError(code: .unavailable, message: "channel is closed"))
      }
      self._connectivityState.continuation.yield(.shutdown)
      group.cancelAll()

    case .none:
      ()
    }
  }

  private func handleNameResolutionResult(
    _ result: NameResolutionResult,
    in group: inout DiscardingTaskGroup
  ) {
    // Ignore empty endpoint lists.
    if result.endpoints.isEmpty { return }

    switch result.serviceConfig ?? .success(self.defaultServiceConfig) {
    case .success(let config):
      // Update per RPC configuration.
      let methodConfig = MethodConfigs(serviceConfig: config)
      self._methodConfig.withLockedValue { $0 = methodConfig }

      let retryThrottle = config.retryThrottling.map { RetryThrottle(policy: $0) }
      self._retryThrottle.withLockedValue { $0 = retryThrottle }

      // Update the load balancer.
      self.updateLoadBalancer(serviceConfig: config, endpoints: result.endpoints, in: &group)

    case .failure:
      self.close()
    }
  }

  enum SupportedLoadBalancerConfig {
    case roundRobin
    case pickFirst(ServiceConfig.LoadBalancingConfig.PickFirst)

    init?(_ config: ServiceConfig.LoadBalancingConfig) {
      if let pickFirst = config.pickFirst {
        self = .pickFirst(pickFirst)
      } else if config.roundRobin != nil {
        self = .roundRobin
      } else {
        return nil
      }
    }

    func matches(loadBalancer: LoadBalancer) -> Bool {
      switch (self, loadBalancer) {
      case (.roundRobin, .roundRobin):
        return true
      case (.pickFirst, .pickFirst):
        return true
      case (.roundRobin, .pickFirst),
        (.pickFirst, .roundRobin):
        return false
      }
    }
  }

  private func updateLoadBalancer(
    serviceConfig: ServiceConfig,
    endpoints: [Endpoint],
    in group: inout DiscardingTaskGroup
  ) {
    assert(!endpoints.isEmpty, "endpoints must be non-empty")

    // Find the first supported config.
    var configFromServiceConfig: SupportedLoadBalancerConfig?
    for config in serviceConfig.loadBalancingConfig {
      if let config = SupportedLoadBalancerConfig(config) {
        configFromServiceConfig = config
        break
      }
    }

    let onUpdatePolicy: GRPCChannel.StateMachine.OnChangeLoadBalancer
    var endpoints = endpoints

    // Fallback to pick-first if no other config applies.
    let loadBalancerConfig = configFromServiceConfig ?? .pickFirst(.init(shuffleAddressList: false))
    switch loadBalancerConfig {
    case .roundRobin:
      onUpdatePolicy = self.state.withLockedValue { state in
        state.changeLoadBalancerKind(to: loadBalancerConfig) {
          let loadBalancer = RoundRobinLoadBalancer(
            connector: self.connector,
            backoff: self.backoff,
            defaultCompression: self.defaultCompression,
            enabledCompression: self.enabledCompression
          )
          return .roundRobin(loadBalancer)
        }
      }

    case .pickFirst(let pickFirst):
      if pickFirst.shuffleAddressList {
        endpoints[0].addresses.shuffle()
      }

      onUpdatePolicy = self.state.withLockedValue { state in
        state.changeLoadBalancerKind(to: loadBalancerConfig) {
          let loadBalancer = PickFirstLoadBalancer(
            connector: self.connector,
            backoff: self.backoff,
            defaultCompression: self.defaultCompression,
            enabledCompression: self.enabledCompression
          )
          return .pickFirst(loadBalancer)
        }
      }
    }

    self.handleLoadBalancerChange(onUpdatePolicy, endpoints: endpoints, in: &group)
  }

  private func handleLoadBalancerChange(
    _ update: StateMachine.OnChangeLoadBalancer,
    endpoints: [Endpoint],
    in group: inout DiscardingTaskGroup
  ) {
    assert(!endpoints.isEmpty, "endpoints must be non-empty")

    switch update {
    case .runLoadBalancer(let new, let old):
      old?.close()
      switch new {
      case .roundRobin(let loadBalancer):
        loadBalancer.updateAddresses(endpoints)
      case .pickFirst(let loadBalancer):
        loadBalancer.updateEndpoint(endpoints.first!)
      }

      group.addTask {
        await new.run()
      }

      group.addTask {
        for await event in new.events {
          self.input.continuation.yield(.handleLoadBalancerEvent(event, new.id))
        }
      }

    case .updateLoadBalancer(let existing):
      switch existing {
      case .roundRobin(let loadBalancer):
        loadBalancer.updateAddresses(endpoints)
      case .pickFirst(let loadBalancer):
        loadBalancer.updateEndpoint(endpoints.first!)
      }

    case .none:
      ()
    }
  }

  private func handleLoadBalancerEvent(
    _ event: LoadBalancerEvent,
    loadBalancerID: LoadBalancerID,
    in group: inout DiscardingTaskGroup,
    iterator: inout RPCAsyncSequence<NameResolutionResult, any Error>.AsyncIterator?
  ) async {
    switch event {
    case .connectivityStateChanged(let connectivityState):
      let actions = self.state.withLockedValue { state in
        state.loadBalancerStateChanged(to: connectivityState, id: loadBalancerID)
      }

      if let newState = actions.publishState {
        self._connectivityState.continuation.yield(newState)
      }

      if let subchannel = actions.close {
        subchannel.close()
      }

      if let resumable = actions.resumeContinuations {
        for continuation in resumable.continuations {
          continuation.resume(with: resumable.result)
        }
      }

      if actions.finish {
        // Fully closed.
        self._connectivityState.continuation.finish()
        self.input.continuation.finish()
      }

    case .requiresNameResolution:
      await self.resolve(iterator: &iterator, in: &group)
    }
  }

  private func resolve(
    iterator: inout RPCAsyncSequence<NameResolutionResult, any Error>.AsyncIterator?,
    in group: inout DiscardingTaskGroup
  ) async {
    guard var iterator = iterator else { return }

    do {
      if let result = try await iterator.next() {
        self.handleNameResolutionResult(result, in: &group)
      } else {
        self.close()
      }
    } catch {
      self.close()
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension GRPCChannel {
  struct StateMachine {
    enum State {
      case notRunning(NotRunning)
      case running(Running)
      case stopping(Stopping)
      case stopped
      case _modifying

      struct NotRunning {
        /// Queue of requests waiting for a load-balancer.
        var queue: RequestQueue
        /// A handle to the name resolver task.
        var nameResolverHandle: CancellableTaskHandle?

        init() {
          self.queue = RequestQueue()
        }
      }

      struct Running {
        /// The connectivity state of the channel.
        var connectivityState: ConnectivityState
        /// The load-balancer currently in use.
        var current: LoadBalancer
        /// The next load-balancer to use. This will be promoted to `current` when it enters the
        /// ready state.
        var next: LoadBalancer?
        /// Previously created load-balancers which are in the process of shutting down.
        var past: [LoadBalancerID: LoadBalancer]
        /// Queue of requests wait for a load-balancer.
        var queue: RequestQueue
        /// A handle to the name resolver task.
        var nameResolverHandle: CancellableTaskHandle?

        init(
          from state: NotRunning,
          loadBalancer: LoadBalancer
        ) {
          self.connectivityState = .idle
          self.current = loadBalancer
          self.next = nil
          self.past = [:]
          self.queue = state.queue
          self.nameResolverHandle = state.nameResolverHandle
        }
      }

      struct Stopping {
        /// Previously created load-balancers which are in the process of shutting down.
        var past: [LoadBalancerID: LoadBalancer]

        init(from state: Running) {
          self.past = state.past
        }

        init(loadBalancers: [LoadBalancerID: LoadBalancer]) {
          self.past = loadBalancers
        }
      }
    }

    /// The current state.
    private var state: State
    /// Whether the channel is running.
    private var running: Bool

    init() {
      self.state = .notRunning(State.NotRunning())
      self.running = false
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension GRPCChannel.StateMachine {
  mutating func start() {
    precondition(!self.running, "channel must only be started once")
    self.running = true
  }

  mutating func setNameResolverTaskHandle(_ handle: CancellableTaskHandle) {
    switch self.state {
    case .notRunning(var state):
      state.nameResolverHandle = handle
      self.state = .notRunning(state)
    case .running, .stopping, .stopped, ._modifying:
      fatalError("Invalid state")
    }
  }

  enum OnChangeLoadBalancer {
    case runLoadBalancer(LoadBalancer, stop: LoadBalancer?)
    case updateLoadBalancer(LoadBalancer)
    case none
  }

  mutating func changeLoadBalancerKind(
    to newLoadBalancerKind: GRPCChannel.SupportedLoadBalancerConfig,
    _ makeLoadBalancer: () -> LoadBalancer
  ) -> OnChangeLoadBalancer {
    let onChangeLoadBalancer: OnChangeLoadBalancer

    switch self.state {
    case .notRunning(let state):
      let loadBalancer = makeLoadBalancer()
      let state = State.Running(from: state, loadBalancer: loadBalancer)
      self.state = .running(state)
      onChangeLoadBalancer = .runLoadBalancer(state.current, stop: nil)

    case .running(var state):
      self.state = ._modifying

      if let next = state.next {
        if newLoadBalancerKind.matches(loadBalancer: next) {
          onChangeLoadBalancer = .updateLoadBalancer(next)
        } else {
          // The 'next' didn't become ready in time. Close it and replace it with a load-balancer
          // of the next kind.
          let nextNext = makeLoadBalancer()
          let previous = state.next
          state.next = nextNext
          state.past[next.id] = next
          onChangeLoadBalancer = .runLoadBalancer(nextNext, stop: previous)
        }
      } else {
        if newLoadBalancerKind.matches(loadBalancer: state.current) {
          onChangeLoadBalancer = .updateLoadBalancer(state.current)
        } else {
          // Create the 'next' load-balancer, it'll replace 'current' when it becomes ready.
          let next = makeLoadBalancer()
          state.next = next
          onChangeLoadBalancer = .runLoadBalancer(next, stop: nil)
        }
      }

      self.state = .running(state)

    case .stopping, .stopped:
      onChangeLoadBalancer = .none

    case ._modifying:
      fatalError("Invalid state")
    }

    return onChangeLoadBalancer
  }

  struct ConnectivityStateChangeActions {
    var close: LoadBalancer? = nil
    var publishState: ConnectivityState? = nil
    var resumeContinuations: ResumableContinuations? = nil
    var finish: Bool = false

    struct ResumableContinuations {
      var continuations: [CheckedContinuation<LoadBalancer, any Error>]
      var result: Result<LoadBalancer, any Error>
    }
  }

  mutating func loadBalancerStateChanged(
    to connectivityState: ConnectivityState,
    id: LoadBalancerID
  ) -> ConnectivityStateChangeActions {
    var actions = ConnectivityStateChangeActions()

    switch self.state {
    case .running(var state):
      self.state = ._modifying

      if id == state.current.id {
        // No change in state, ignore.
        if state.connectivityState == connectivityState {
          self.state = .running(state)
          break
        }

        state.connectivityState = connectivityState
        actions.publishState = connectivityState

        switch connectivityState {
        case .ready:
          // Current load-balancer became ready; resume all continuations in the queue.
          let continuations = state.queue.removeAll()
          actions.resumeContinuations = ConnectivityStateChangeActions.ResumableContinuations(
            continuations: continuations,
            result: .success(state.current)
          )

        case .transientFailure, .shutdown:  // shutdown includes shutting down
          // Current load-balancer failed. Remove all the 'fast-failing' continuations in the
          // queue, these are RPCs which set the 'wait for ready' option to false. The rest of
          // the entries in the queue will wait for a load-balancer to become ready.
          let continuations = state.queue.removeFastFailingEntries()
          actions.resumeContinuations = ConnectivityStateChangeActions.ResumableContinuations(
            continuations: continuations,
            result: .failure(RPCError(code: .unavailable, message: "channel isn't ready"))
          )

        case .idle, .connecting:
          ()  // Ignore.
        }
      } else if let next = state.next, next.id == id {
        // State change came from the next LB, if it's now ready promote it to be the current.
        switch connectivityState {
        case .ready:
          // Next load-balancer is ready, promote it to current.
          let previous = state.current
          state.past[previous.id] = previous
          state.current = next
          state.next = nil

          actions.close = previous

          if state.connectivityState != connectivityState {
            actions.publishState = connectivityState
          }

          actions.resumeContinuations = ConnectivityStateChangeActions.ResumableContinuations(
            continuations: state.queue.removeAll(),
            result: .success(next)
          )

        case .idle, .connecting, .transientFailure, .shutdown:
          ()
        }
      }

      self.state = .running(state)

    case .stopping(var state):
      self.state = ._modifying

      // Remove the load balancer if it's now shutdown.
      switch connectivityState {
      case .shutdown:
        state.past.removeValue(forKey: id)
      case .idle, .connecting, .ready, .transientFailure:
        ()
      }

      // If that was the last load-balancer then finish the input streams so that the channel
      // eventually finishes.
      if state.past.isEmpty {
        actions.finish = true
        self.state = .stopped
      } else {
        self.state = .stopping(state)
      }

    case .notRunning, .stopped:
      ()

    case ._modifying:
      fatalError("Invalid state")
    }

    return actions
  }

  enum OnMakeStream {
    /// Use the given load-balancer to make a stream.
    case useLoadBalancer(LoadBalancer)
    /// Join the queue and wait until a load-balancer becomes ready.
    case joinQueue
    /// Fail the stream request, the channel isn't in a suitable state.
    case failRPC
  }

  func makeStream(waitForReady: Bool) -> OnMakeStream {
    let onMakeStream: OnMakeStream

    switch self.state {
    case .notRunning:
      onMakeStream = .joinQueue

    case .running(let state):
      switch state.connectivityState {
      case .idle, .connecting:
        onMakeStream = .joinQueue
      case .ready:
        onMakeStream = .useLoadBalancer(state.current)
      case .transientFailure:
        onMakeStream = waitForReady ? .joinQueue : .failRPC
      case .shutdown:
        onMakeStream = .failRPC
      }

    case .stopping, .stopped:
      onMakeStream = .failRPC

    case ._modifying:
      fatalError("Invalid state")
    }

    return onMakeStream
  }

  mutating func enqueue(
    continuation: CheckedContinuation<LoadBalancer, any Error>,
    waitForReady: Bool,
    id: QueueEntryID
  ) -> Bool {
    switch self.state {
    case .notRunning(var state):
      self.state = ._modifying
      state.queue.append(continuation: continuation, waitForReady: waitForReady, id: id)
      self.state = .notRunning(state)
      return true
    case .running(var state):
      self.state = ._modifying
      state.queue.append(continuation: continuation, waitForReady: waitForReady, id: id)
      self.state = .running(state)
      return true
    case .stopping, .stopped:
      return false
    case ._modifying:
      fatalError("Invalid state")
    }
  }

  mutating func dequeueContinuation(
    id: QueueEntryID
  ) -> CheckedContinuation<LoadBalancer, any Error>? {
    switch self.state {
    case .notRunning(var state):
      self.state = ._modifying
      let continuation = state.queue.removeEntry(withID: id)
      self.state = .notRunning(state)
      return continuation

    case .running(var state):
      self.state = ._modifying
      let continuation = state.queue.removeEntry(withID: id)
      self.state = .running(state)
      return continuation

    case .stopping, .stopped:
      return nil

    case ._modifying:
      fatalError("Invalid state")
    }
  }

  enum OnClose {
    case none
    case cancelAll([RequestQueue.Continuation])
    case close(LoadBalancer, LoadBalancer?, CancellableTaskHandle?, [RequestQueue.Continuation])
  }

  mutating func close() -> OnClose {
    let onClose: OnClose

    switch self.state {
    case .notRunning(var state):
      self.state = .stopped
      onClose = .cancelAll(state.queue.removeAll())

    case .running(var state):
      let continuations = state.queue.removeAll()
      onClose = .close(state.current, state.next, state.nameResolverHandle, continuations)

      state.past[state.current.id] = state.current
      if let next = state.next {
        state.past[next.id] = next
      }

      self.state = .stopping(State.Stopping(loadBalancers: state.past))

    case .stopping, .stopped:
      onClose = .none

    case ._modifying:
      fatalError("Invalid state")
    }

    return onClose
  }
}
