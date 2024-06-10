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

import GRPCCore

/// A load-balancer which has a single subchannel.
///
/// This load-balancer starts in an 'idle' state and begins connecting when a set of addresses is
/// provided to it with ``updateEndpoint(_:)``. Repeated calls to ``updateEndpoint(_:)`` will
/// update the subchannel gracefully: RPCs will continue to use the old subchannel until the new
/// subchannel becomes ready.
///
/// You must call ``close()`` on the load-balancer when it's no longer required. This will move
/// it to the ``ConnectivityState/shutdown`` state: existing RPCs may continue but all subsequent
/// calls to ``makeStream(descriptor:options:)`` will fail.
///
/// To use this load-balancer you must run it in a task:
///
/// ```swift
/// await withDiscardingTaskGroup { group in
///   // Run the load-balancer
///   group.addTask { await pickFirst.run() }
///
///   // Update its endpoint.
///   let endpoint = Endpoint(
///     addresses: [
///       .ipv4(host: "127.0.0.1", port: 1001),
///       .ipv4(host: "127.0.0.1", port: 1002),
///       .ipv4(host: "127.0.0.1", port: 1003)
///     ]
///   )
///   pickFirst.updateEndpoint(endpoint)
///
///   // Consume state update events
///   for await event in pickFirst.events {
///     switch event {
///     case .connectivityStateChanged(.ready):
///       // ...
///     default:
///       // ...
///     }
///   }
/// }
/// ```
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct PickFirstLoadBalancer {
  enum Input: Sendable, Hashable {
    /// Update the addresses used by the load balancer to the following endpoints.
    case updateEndpoint(Endpoint)
    /// Close the load balancer.
    case close
  }

  /// Events which can happen to the load balancer.
  private let event:
    (
      stream: AsyncStream<LoadBalancerEvent>,
      continuation: AsyncStream<LoadBalancerEvent>.Continuation
    )

  /// Inputs which this load balancer should react to.
  private let input: (stream: AsyncStream<Input>, continuation: AsyncStream<Input>.Continuation)

  /// A connector, capable of creating connections.
  private let connector: any HTTP2Connector

  /// Connection backoff configuration.
  private let backoff: ConnectionBackoff

  /// The default compression algorithm to use. Can be overridden on a per-call basis.
  private let defaultCompression: CompressionAlgorithm

  /// The set of enabled compression algorithms.
  private let enabledCompression: CompressionAlgorithmSet

  /// The state of the load-balancer.
  private let state: _LockedValueBox<State>

  /// The ID of this load balancer.
  internal let id: LoadBalancerID

  init(
    connector: any HTTP2Connector,
    backoff: ConnectionBackoff,
    defaultCompression: CompressionAlgorithm,
    enabledCompression: CompressionAlgorithmSet
  ) {
    self.connector = connector
    self.backoff = backoff
    self.defaultCompression = defaultCompression
    self.enabledCompression = enabledCompression
    self.id = LoadBalancerID()
    self.state = _LockedValueBox(State())

    self.event = AsyncStream.makeStream(of: LoadBalancerEvent.self)
    self.input = AsyncStream.makeStream(of: Input.self)
    // The load balancer starts in the idle state.
    self.event.continuation.yield(.connectivityStateChanged(.idle))
  }

  /// A stream of events which can happen to the load balancer.
  var events: AsyncStream<LoadBalancerEvent> {
    self.event.stream
  }

  /// Runs the load balancer, returning when it has closed.
  ///
  /// You can monitor events which happen on the load balancer with ``events``.
  func run() async {
    await withDiscardingTaskGroup { group in
      for await input in self.input.stream {
        switch input {
        case .updateEndpoint(let endpoint):
          self.handleUpdateEndpoint(endpoint, in: &group)
        case .close:
          self.handleCloseInput()
        }
      }
    }

    if Task.isCancelled {
      // Finish the event stream as it's unlikely to have been finished by a regular code path.
      self.event.continuation.finish()
    }
  }

  /// Update the addresses used by the load balancer.
  ///
  /// This may result in new subchannels being created and some subchannels being removed.
  func updateEndpoint(_ endpoint: Endpoint) {
    self.input.continuation.yield(.updateEndpoint(endpoint))
  }

  /// Close the load balancer, and all subchannels it manages.
  func close() {
    self.input.continuation.yield(.close)
  }

  /// Pick a ready subchannel from the load balancer.
  ///
  /// - Returns: A subchannel, or `nil` if there aren't any ready subchannels.
  func pickSubchannel() -> Subchannel? {
    let onPickSubchannel = self.state.withLockedValue { $0.pickSubchannel() }
    switch onPickSubchannel {
    case .picked(let subchannel):
      return subchannel
    case .notAvailable(let subchannel):
      subchannel?.connect()
      return nil
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension PickFirstLoadBalancer {
  private func handleUpdateEndpoint(_ endpoint: Endpoint, in group: inout DiscardingTaskGroup) {
    if endpoint.addresses.isEmpty { return }

    let onUpdate = self.state.withLockedValue { state in
      state.updateEndpoint(endpoint) { endpoint, id in
        Subchannel(
          endpoint: endpoint,
          id: id,
          connector: self.connector,
          backoff: self.backoff,
          defaultCompression: self.defaultCompression,
          enabledCompression: self.enabledCompression
        )
      }
    }

    switch onUpdate {
    case .connect(let newSubchannel, close: let oldSubchannel):
      self.runSubchannel(newSubchannel, in: &group)
      oldSubchannel?.close()

    case .none:
      ()
    }
  }

  private func runSubchannel(
    _ subchannel: Subchannel,
    in group: inout DiscardingTaskGroup
  ) {
    // Start running it and tell it to connect.
    subchannel.connect()
    group.addTask {
      await subchannel.run()
    }

    group.addTask {
      for await event in subchannel.events {
        switch event {
        case .connectivityStateChanged(let state):
          self.handleSubchannelConnectivityStateChange(state, id: subchannel.id)
        case .goingAway:
          self.handleGoAway(id: subchannel.id)
        case .requiresNameResolution:
          self.event.continuation.yield(.requiresNameResolution)
        }
      }
    }
  }

  private func handleSubchannelConnectivityStateChange(
    _ connectivityState: ConnectivityState,
    id: SubchannelID
  ) {
    let onUpdateState = self.state.withLockedValue {
      $0.updateSubchannelConnectivityState(connectivityState, id: id)
    }

    switch onUpdateState {
    case .close(let subchannel):
      subchannel.close()
    case .closeAndPublishStateChange(let subchannel, let connectivityState):
      subchannel.close()
      self.event.continuation.yield(.connectivityStateChanged(connectivityState))
    case .publishStateChange(let connectivityState):
      self.event.continuation.yield(.connectivityStateChanged(connectivityState))
    case .closed:
      self.event.continuation.finish()
      self.input.continuation.finish()
    case .none:
      ()
    }
  }

  private func handleGoAway(id: SubchannelID) {
    self.state.withLockedValue { state in
      state.receivedGoAway(id: id)
    }
  }

  private func handleCloseInput() {
    let onClose = self.state.withLockedValue { $0.close() }
    switch onClose {
    case .closeSubchannels(let subchannel1, let subchannel2):
      self.event.continuation.yield(.connectivityStateChanged(.shutdown))
      subchannel1.close()
      subchannel2?.close()

    case .closed:
      self.event.continuation.yield(.connectivityStateChanged(.shutdown))
      self.event.continuation.finish()
      self.input.continuation.finish()

    case .none:
      ()
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension PickFirstLoadBalancer {
  enum State: Sendable {
    case active(Active)
    case closing(Closing)
    case closed

    init() {
      self = .active(Active())
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension PickFirstLoadBalancer.State {
  struct Active: Sendable {
    var endpoint: Endpoint?
    var connectivityState: ConnectivityState
    var current: Subchannel?
    var next: Subchannel?
    var parked: [SubchannelID: Subchannel]
    var isCurrentGoingAway: Bool

    init() {
      self.endpoint = nil
      self.connectivityState = .idle
      self.current = nil
      self.next = nil
      self.parked = [:]
      self.isCurrentGoingAway = false
    }
  }

  struct Closing: Sendable {
    var parked: [SubchannelID: Subchannel]

    init(from state: Active) {
      self.parked = state.parked
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension PickFirstLoadBalancer.State.Active {
  mutating func updateEndpoint(
    _ endpoint: Endpoint,
    makeSubchannel: (_ endpoint: Endpoint, _ id: SubchannelID) -> Subchannel
  ) -> PickFirstLoadBalancer.State.OnUpdateEndpoint {
    if self.endpoint == endpoint { return .none }

    let onUpdateEndpoint: PickFirstLoadBalancer.State.OnUpdateEndpoint

    let id = SubchannelID()
    let newSubchannel = makeSubchannel(endpoint, id)

    switch (self.current, self.next) {
    case (.some(let current), .none):
      if self.connectivityState == .idle {
        // Current subchannel is idle and we have a new endpoint, move straight to the new
        // subchannel.
        self.current = newSubchannel
        self.parked[current.id] = current
        onUpdateEndpoint = .connect(newSubchannel, close: current)
      } else {
        // Current subchannel is in a non-idle state, set it as the next subchannel and promote
        // it when it becomes ready.
        self.next = newSubchannel
        onUpdateEndpoint = .connect(newSubchannel, close: nil)
      }

    case (.some, .some(let next)):
      // Current and next subchannel exist. Replace the next subchannel.
      self.next = newSubchannel
      self.parked[next.id] = next
      onUpdateEndpoint = .connect(newSubchannel, close: next)

    case (.none, .none):
      self.current = newSubchannel
      onUpdateEndpoint = .connect(newSubchannel, close: nil)

    case (.none, .some(let next)):
      self.current = newSubchannel
      self.next = nil
      self.parked[next.id] = next
      onUpdateEndpoint = .connect(newSubchannel, close: next)
    }

    return onUpdateEndpoint
  }

  mutating func updateSubchannelConnectivityState(
    _ connectivityState: ConnectivityState,
    id: SubchannelID
  ) -> (PickFirstLoadBalancer.State.OnConnectivityStateUpdate, PickFirstLoadBalancer.State) {
    let onUpdate: PickFirstLoadBalancer.State.OnConnectivityStateUpdate

    if let current = self.current, current.id == id {
      if connectivityState == self.connectivityState {
        onUpdate = .none
      } else {
        self.connectivityState = connectivityState
        onUpdate = .publishStateChange(connectivityState)
      }
    } else if let next = self.next, next.id == id {
      // if it becomes ready then promote it
      switch connectivityState {
      case .ready:
        if self.connectivityState != connectivityState {
          self.connectivityState = connectivityState

          if let current = self.current {
            onUpdate = .closeAndPublishStateChange(current, connectivityState)
          } else {
            onUpdate = .publishStateChange(connectivityState)
          }

          self.current = next
          self.isCurrentGoingAway = false
        } else {
          // No state change to publish, just roll over.
          onUpdate = self.current.map { .close($0) } ?? .none
          self.current = next
          self.isCurrentGoingAway = false
        }

      case .idle, .connecting, .transientFailure, .shutdown:
        onUpdate = .none
      }

    } else {
      switch connectivityState {
      case .idle:
        if let subchannel = self.parked[id] {
          onUpdate = .close(subchannel)
        } else {
          onUpdate = .none
        }

      case .shutdown:
        self.parked.removeValue(forKey: id)
        onUpdate = .none

      case .connecting, .ready, .transientFailure:
        onUpdate = .none
      }
    }

    return (onUpdate, .active(self))
  }

  mutating func receivedGoAway(id: SubchannelID) {
    if let current = self.current, current.id == id {
      // When receiving a GOAWAY the subchannel will ask for an address to be re-resolved and the
      // connection will eventually become idle. At this point we wait: the connection remains
      // in its current state.
      self.isCurrentGoingAway = true
    } else if let next = self.next, next.id == id {
      // The next connection is going away, park it.
      // connection.
      self.next = nil
      self.parked[next.id] = next
    }
  }

  mutating func close() -> (PickFirstLoadBalancer.State.OnClose, PickFirstLoadBalancer.State) {
    let onClose: PickFirstLoadBalancer.State.OnClose
    let nextState: PickFirstLoadBalancer.State

    if let current = self.current {
      self.parked[current.id] = current
      if let next = self.next {
        self.parked[next.id] = next
        onClose = .closeSubchannels(current, next)
      } else {
        onClose = .closeSubchannels(current, nil)
      }
      nextState = .closing(PickFirstLoadBalancer.State.Closing(from: self))
    } else {
      onClose = .closed
      nextState = .closed
    }

    return (onClose, nextState)
  }

  func pickSubchannel() -> PickFirstLoadBalancer.State.OnPickSubchannel {
    let onPick: PickFirstLoadBalancer.State.OnPickSubchannel

    if let current = self.current, !self.isCurrentGoingAway {
      switch self.connectivityState {
      case .idle:
        onPick = .notAvailable(current)
      case .ready:
        onPick = .picked(current)
      case .connecting, .transientFailure, .shutdown:
        onPick = .notAvailable(nil)
      }
    } else {
      onPick = .notAvailable(nil)
    }

    return onPick
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension PickFirstLoadBalancer.State.Closing {
  mutating func updateSubchannelConnectivityState(
    _ connectivityState: ConnectivityState,
    id: SubchannelID
  ) -> (PickFirstLoadBalancer.State.OnConnectivityStateUpdate, PickFirstLoadBalancer.State) {
    let onUpdate: PickFirstLoadBalancer.State.OnConnectivityStateUpdate
    let nextState: PickFirstLoadBalancer.State

    switch connectivityState {
    case .idle:
      if let subchannel = self.parked[id] {
        onUpdate = .close(subchannel)
      } else {
        onUpdate = .none
      }
      nextState = .closing(self)

    case .shutdown:
      if self.parked.removeValue(forKey: id) != nil {
        if self.parked.isEmpty {
          onUpdate = .closed
          nextState = .closed
        } else {
          onUpdate = .none
          nextState = .closing(self)
        }
      } else {
        onUpdate = .none
        nextState = .closing(self)
      }

    case .connecting, .ready, .transientFailure:
      onUpdate = .none
      nextState = .closing(self)
    }

    return (onUpdate, nextState)
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension PickFirstLoadBalancer.State {
  enum OnUpdateEndpoint {
    case connect(Subchannel, close: Subchannel?)
    case none
  }

  mutating func updateEndpoint(
    _ endpoint: Endpoint,
    makeSubchannel: (_ endpoint: Endpoint, _ id: SubchannelID) -> Subchannel
  ) -> OnUpdateEndpoint {
    let onUpdateEndpoint: OnUpdateEndpoint

    switch self {
    case .active(var state):
      onUpdateEndpoint = state.updateEndpoint(endpoint) { endpoint, id in
        makeSubchannel(endpoint, id)
      }
      self = .active(state)

    case .closing, .closed:
      onUpdateEndpoint = .none
    }

    return onUpdateEndpoint
  }

  enum OnConnectivityStateUpdate {
    case closeAndPublishStateChange(Subchannel, ConnectivityState)
    case publishStateChange(ConnectivityState)
    case close(Subchannel)
    case closed
    case none
  }

  mutating func updateSubchannelConnectivityState(
    _ connectivityState: ConnectivityState,
    id: SubchannelID
  ) -> OnConnectivityStateUpdate {
    let onUpdateState: OnConnectivityStateUpdate

    switch self {
    case .active(var state):
      (onUpdateState, self) = state.updateSubchannelConnectivityState(connectivityState, id: id)
    case .closing(var state):
      (onUpdateState, self) = state.updateSubchannelConnectivityState(connectivityState, id: id)
    case .closed:
      onUpdateState = .none
    }

    return onUpdateState
  }

  mutating func receivedGoAway(id: SubchannelID) {
    switch self {
    case .active(var state):
      state.receivedGoAway(id: id)
      self = .active(state)
    case .closing, .closed:
      ()
    }
  }

  enum OnClose {
    case closeSubchannels(Subchannel, Subchannel?)
    case closed
    case none
  }

  mutating func close() -> OnClose {
    let onClose: OnClose

    switch self {
    case .active(var state):
      (onClose, self) = state.close()
    case .closing, .closed:
      onClose = .none
    }

    return onClose
  }

  enum OnPickSubchannel {
    case picked(Subchannel)
    case notAvailable(Subchannel?)
  }

  func pickSubchannel() -> OnPickSubchannel {
    switch self {
    case .active(let state):
      return state.pickSubchannel()
    case .closing, .closed:
      return .notAvailable(nil)
    }
  }
}
