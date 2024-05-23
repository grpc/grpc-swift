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

/// A load-balancer which maintains to a set of subchannels and uses round-robin to pick a
/// subchannel when picking a subchannel to use.
///
/// This load-balancer starts in an 'idle' state and begins connecting when a set of addresses is
/// provided to it with ``updateAddresses(_:)``. Repeated calls to ``updateAddresses(_:)`` will
/// update the subchannels gracefully: new subchannels will be added for new addresses and existing
/// subchannels will be removed if their addresses are no longer present.
///
/// The state of the load-balancer is aggregated across the state of its subchannels, changes in
/// the aggregate state are reported up via ``events``.
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
///   group.addTask { await roundRobin.run() }
///
///   // Update its address list
///   let endpoints: [Endpoint] = [
///     Endpoint(addresses: [.ipv4(host: "127.0.0.1", port: 1001)]),
///     Endpoint(addresses: [.ipv4(host: "127.0.0.1", port: 1002)]),
///     Endpoint(addresses: [.ipv4(host: "127.0.0.1", port: 1003)])
///   ]
///   roundRobin.updateAddresses(endpoints)
///
///   // Consume state update events
///   for await event in roundRobin.events {
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
struct RoundRobinLoadBalancer {
  enum Input: Sendable, Hashable {
    /// Update the addresses used by the load balancer to the following endpoints.
    case updateAddresses([Endpoint])
    /// Close the load balancer.
    case close
  }

  /// A key for an endpoint which identifies it uniquely, regardless of the ordering of addresses.
  private struct EndpointKey: Hashable, Sendable, CustomStringConvertible {
    /// Opaque data.
    private let opaque: [String]

    /// The endpoint this key is for.
    let endpoint: Endpoint

    init(_ endpoint: Endpoint) {
      self.endpoint = endpoint
      self.opaque = endpoint.addresses.map { String(describing: $0) }.sorted()
    }

    var description: String {
      String(describing: self.endpoint.addresses)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(self.opaque)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.opaque == rhs.opaque
    }
  }

  /// Events which can happen to the load balancer.
  private let event:
    (
      stream: AsyncStream<LoadBalancerEvent>,
      continuation: AsyncStream<LoadBalancerEvent>.Continuation
    )

  /// Inputs which this load balancer should react to.
  private let input: (stream: AsyncStream<Input>, continuation: AsyncStream<Input>.Continuation)

  /// The state of the load balancer.
  private let state: _LockedValueBox<State>

  /// A connector, capable of creating connections.
  private let connector: any HTTP2Connector

  /// Connection backoff configuration.
  private let backoff: ConnectionBackoff

  /// The default compression algorithm to use. Can be overridden on a per-call basis.
  private let defaultCompression: CompressionAlgorithm

  /// The set of enabled compression algorithms.
  private let enabledCompression: CompressionAlgorithmSet

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

    self.event = AsyncStream.makeStream(of: LoadBalancerEvent.self)
    self.input = AsyncStream.makeStream(of: Input.self)
    self.state = _LockedValueBox(.active(State.Active()))

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
        case .updateAddresses(let addresses):
          self.handleUpdateAddresses(addresses, in: &group)
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
  func updateAddresses(_ endpoints: [Endpoint]) {
    self.input.continuation.yield(.updateAddresses(endpoints))
  }

  /// Close the load balancer, and all subchannels it manages.
  func close() {
    self.input.continuation.yield(.close)
  }

  /// Pick a ready subchannel from the load balancer.
  ///
  /// - Returns: A subchannel, or `nil` if there aren't any ready subchannels.
  func pickSubchannel() -> Subchannel? {
    switch self.state.withLockedValue({ $0.pickSubchannel() }) {
    case .picked(let subchannel):
      return subchannel

    case .notAvailable(let subchannels):
      // Tell the subchannels to start connecting.
      for subchannel in subchannels {
        subchannel.connect()
      }
      return nil
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension RoundRobinLoadBalancer {
  /// Handles an update in endpoints.
  ///
  /// The load-balancer will diff the set of endpoints with the existing set of endpoints:
  /// - endpoints which are new will have subchannels created for them,
  /// - endpoints which existed previously but are not present in `endpoints` are closed,
  /// - endpoints which existed previously and are still present in `endpoints` are untouched.
  ///
  /// This process is gradual: the load-balancer won't remove an old endpoint until a subchannel
  /// for a corresponding new subchannel becomes ready.
  ///
  /// - Parameters:
  ///   - endpoints: Endpoints which should have subchannels. Must not be empty.
  ///   - group: The group which should manage and run new subchannels.
  private func handleUpdateAddresses(_ endpoints: [Endpoint], in group: inout DiscardingTaskGroup) {
    if endpoints.isEmpty { return }

    // Compute the keys for each endpoint.
    let newEndpoints = Set(endpoints.map { EndpointKey($0) })

    let (added, removed, newState) = self.state.withLockedValue { state in
      state.updateSubchannels(newEndpoints: newEndpoints) { endpoint, id in
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

    // Publish the new connectivity state.
    if let newState = newState {
      self.event.continuation.yield(.connectivityStateChanged(newState))
    }

    // Run each of the new subchannels.
    for subchannel in added {
      let key = EndpointKey(subchannel.endpoint)
      self.runSubchannel(subchannel, forKey: key, in: &group)
    }

    // Old subchannels are removed when new subchannels become ready. Excess subchannels are only
    // present if there are more to remove than to add. These are the excess subchannels which
    // are closed now.
    for subchannel in removed {
      subchannel.close()
    }
  }

  private func runSubchannel(
    _ subchannel: Subchannel,
    forKey key: EndpointKey,
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
          self.handleSubchannelConnectivityStateChange(state, key: key)
        case .goingAway:
          self.handleSubchannelGoingAway(key: key)
        case .requiresNameResolution:
          self.event.continuation.yield(.requiresNameResolution)
        }
      }
    }
  }

  private func handleSubchannelConnectivityStateChange(
    _ connectivityState: ConnectivityState,
    key: EndpointKey
  ) {
    let onChange = self.state.withLockedValue { state in
      state.updateSubchannelConnectivityState(connectivityState, key: key)
    }

    switch onChange {
    case .publishStateChange(let aggregateState):
      self.event.continuation.yield(.connectivityStateChanged(aggregateState))

    case .closeAndPublishStateChange(let subchannel, let aggregateState):
      self.event.continuation.yield(.connectivityStateChanged(aggregateState))
      subchannel.close()

    case .close(let subchannel):
      subchannel.close()

    case .closed:
      // All subchannels are closed; finish the streams so the run loop exits.
      self.event.continuation.finish()
      self.input.continuation.finish()

    case .none:
      ()
    }
  }

  private func handleSubchannelGoingAway(key: EndpointKey) {
    switch self.state.withLockedValue({ $0.parkSubchannel(withKey: key) }) {
    case .closeAndUpdateState(_, let connectivityState):
      // No need to close the subchannel, it's already going away and will close itself.
      if let connectivityState = connectivityState {
        self.event.continuation.yield(.connectivityStateChanged(connectivityState))
      }
    case .none:
      ()
    }
  }

  private func handleCloseInput() {
    switch self.state.withLockedValue({ $0.close() }) {
    case .closeSubchannels(let subchannels):
      // Publish a new shutdown state, this LB is no longer usable for new RPCs.
      self.event.continuation.yield(.connectivityStateChanged(.shutdown))

      // Close the subchannels.
      for subchannel in subchannels {
        subchannel.close()
      }

    case .closed:
      // No subchannels to close.
      self.event.continuation.yield(.connectivityStateChanged(.shutdown))
      self.event.continuation.finish()
      self.input.continuation.finish()

    case .none:
      ()
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension RoundRobinLoadBalancer {
  private enum State {
    case active(Active)
    case closing(Closing)
    case closed

    struct Active {
      private(set) var aggregateConnectivityState: ConnectivityState
      private var picker: Picker?

      var endpoints: [Endpoint]
      var subchannels: [EndpointKey: SubchannelState]
      var parkedSubchannels: [EndpointKey: Subchannel]

      init() {
        self.endpoints = []
        self.subchannels = [:]
        self.parkedSubchannels = [:]
        self.aggregateConnectivityState = .idle
        self.picker = nil
      }

      mutating func updateConnectivityState(
        _ state: ConnectivityState,
        key: EndpointKey
      ) -> OnSubchannelConnectivityStateUpdate {
        if let changed = self.subchannels[key]?.updateState(state) {
          guard changed else { return .none }

          let subchannelToClose: Subchannel?

          switch state {
          case .ready:
            if let index = self.subchannels.firstIndex(where: { $0.value.markedForRemoval }) {
              let (key, subchannelState) = self.subchannels.remove(at: index)
              self.parkedSubchannels[key] = subchannelState.subchannel
              subchannelToClose = subchannelState.subchannel
            } else {
              subchannelToClose = nil
            }

          case .idle, .connecting, .transientFailure, .shutdown:
            subchannelToClose = nil
          }

          let aggregateState = self.refreshPickerAndAggregateState()

          switch (subchannelToClose, aggregateState) {
          case (.some(let subchannel), .some(let state)):
            return .closeAndPublishStateChange(subchannel, state)
          case (.some(let subchannel), .none):
            return .close(subchannel)
          case (.none, .some(let state)):
            return .publishStateChange(state)
          case (.none, .none):
            return .none
          }
        } else {
          switch state {
          case .idle, .connecting, .ready, .transientFailure:
            ()
          case .shutdown:
            self.parkedSubchannels.removeValue(forKey: key)
          }

          return .none
        }
      }

      mutating func refreshPickerAndAggregateState() -> ConnectivityState? {
        let ready = self.subchannels.values.compactMap { $0.state == .ready ? $0.subchannel : nil }
        self.picker = Picker(subchannels: ready)

        let aggregate = ConnectivityState.aggregate(self.subchannels.values.map { $0.state })
        if aggregate == self.aggregateConnectivityState {
          return nil
        } else {
          self.aggregateConnectivityState = aggregate
          return aggregate
        }
      }

      mutating func pick() -> Subchannel? {
        self.picker?.pick()
      }

      mutating func markForRemoval(
        _ keys: some Sequence<EndpointKey>,
        numberToRemoveNow: Int
      ) -> [Subchannel] {
        var numberToRemoveNow = numberToRemoveNow
        var keyIterator = keys.makeIterator()
        var subchannelsToClose = [Subchannel]()

        while numberToRemoveNow > 0, let key = keyIterator.next() {
          if let subchannelState = self.subchannels.removeValue(forKey: key) {
            numberToRemoveNow -= 1
            self.parkedSubchannels[key] = subchannelState.subchannel
            subchannelsToClose.append(subchannelState.subchannel)
          }
        }

        while let key = keyIterator.next() {
          self.subchannels[key]?.markForRemoval()
        }

        return subchannelsToClose
      }

      mutating func registerSubchannels(
        withKeys keys: some Sequence<EndpointKey>,
        _ makeSubchannel: (_ endpoint: Endpoint, _ id: SubchannelID) -> Subchannel
      ) -> [Subchannel] {
        var subchannels = [Subchannel]()

        for key in keys {
          let subchannel = makeSubchannel(key.endpoint, SubchannelID())
          subchannels.append(subchannel)
          self.subchannels[key] = SubchannelState(subchannel: subchannel)
        }

        return subchannels
      }
    }

    struct Closing {
      enum Reason: Sendable, Hashable {
        case goAway
        case user
      }

      var reason: Reason
      var parkedSubchannels: [EndpointKey: Subchannel]

      mutating func updateConnectivityState(_ state: ConnectivityState, key: EndpointKey) -> Bool {
        switch state {
        case .idle, .connecting, .ready, .transientFailure:
          ()
        case .shutdown:
          self.parkedSubchannels.removeValue(forKey: key)
        }

        return self.parkedSubchannels.isEmpty
      }
    }

    struct SubchannelState {
      var subchannel: Subchannel
      var state: ConnectivityState
      var markedForRemoval: Bool

      init(subchannel: Subchannel) {
        self.subchannel = subchannel
        self.state = .idle
        self.markedForRemoval = false
      }

      mutating func updateState(_ newState: ConnectivityState) -> Bool {
        // The transition from transient failure to connecting is ignored.
        //
        // See: https://github.com/grpc/grpc/blob/master/doc/load-balancing.md
        if self.state == .transientFailure, newState == .connecting {
          return false
        }

        let oldState = self.state
        self.state = newState
        return oldState != newState
      }

      mutating func markForRemoval() {
        self.markedForRemoval = true
      }
    }

    struct Picker {
      private var subchannels: [Subchannel]
      private var index: Int

      init?(subchannels: [Subchannel]) {
        if subchannels.isEmpty { return nil }

        self.subchannels = subchannels
        self.index = (0 ..< subchannels.count).randomElement()!
      }

      mutating func pick() -> Subchannel {
        defer {
          self.index = (self.index + 1) % self.subchannels.count
        }
        return self.subchannels[self.index]
      }
    }

    mutating func updateSubchannels(
      newEndpoints: Set<EndpointKey>,
      makeSubchannel: (_ endpoint: Endpoint, _ id: SubchannelID) -> Subchannel
    ) -> (run: [Subchannel], close: [Subchannel], newState: ConnectivityState?) {
      switch self {
      case .active(var state):
        let existingEndpoints = Set(state.subchannels.keys)
        let keysToAdd = newEndpoints.subtracting(existingEndpoints)
        let keysToRemove = existingEndpoints.subtracting(newEndpoints)

        if keysToRemove.isEmpty && keysToAdd.isEmpty {
          // Nothing to do.
          return (run: [], close: [], newState: nil)
        }

        // The load balancer should keep subchannels to remove in service until new subchannels
        // can replace each of them so that requests can continue to be served.
        //
        // If there are more keys to remove than to add, remove some now.
        let numberToRemoveNow = max(keysToRemove.count - keysToAdd.count, 0)

        let removed = state.markForRemoval(keysToRemove, numberToRemoveNow: numberToRemoveNow)
        let added = state.registerSubchannels(withKeys: keysToAdd, makeSubchannel)

        let newState = state.refreshPickerAndAggregateState()
        self = .active(state)
        return (run: added, close: removed, newState: newState)

      case .closing, .closed:
        // Nothing to do.
        return (run: [], close: [], newState: nil)
      }

    }

    enum OnParkChannel {
      case closeAndUpdateState(Subchannel, ConnectivityState?)
      case none
    }

    mutating func parkSubchannel(withKey key: EndpointKey) -> OnParkChannel {
      switch self {
      case .active(var state):
        guard let subchannelState = state.subchannels.removeValue(forKey: key) else {
          return .none
        }

        // Parking the subchannel may invalidate the picker and the aggregate state, refresh both.
        state.parkedSubchannels[key] = subchannelState.subchannel
        let newState = state.refreshPickerAndAggregateState()
        self = .active(state)
        return .closeAndUpdateState(subchannelState.subchannel, newState)

      case .closing, .closed:
        return .none
      }
    }

    mutating func registerSubchannels(
      withKeys keys: some Sequence<EndpointKey>,
      _ makeSubchannel: (Endpoint) -> Subchannel
    ) -> [Subchannel] {
      switch self {
      case .active(var state):
        var subchannels = [Subchannel]()

        for key in keys {
          let subchannel = makeSubchannel(key.endpoint)
          subchannels.append(subchannel)
          state.subchannels[key] = SubchannelState(subchannel: subchannel)
        }

        self = .active(state)
        return subchannels

      case .closing, .closed:
        return []
      }
    }

    enum OnSubchannelConnectivityStateUpdate {
      case closeAndPublishStateChange(Subchannel, ConnectivityState)
      case publishStateChange(ConnectivityState)
      case close(Subchannel)
      case closed
      case none
    }

    mutating func updateSubchannelConnectivityState(
      _ connectivityState: ConnectivityState,
      key: EndpointKey
    ) -> OnSubchannelConnectivityStateUpdate {
      switch self {
      case .active(var state):
        let result = state.updateConnectivityState(connectivityState, key: key)
        self = .active(state)
        return result

      case .closing(var state):
        if state.updateConnectivityState(connectivityState, key: key) {
          self = .closed
          return .closed
        } else {
          self = .closing(state)
          return .none
        }

      case .closed:
        return .none
      }
    }

    enum OnClose {
      case closeSubchannels([Subchannel])
      case closed
      case none
    }

    mutating func close() -> OnClose {
      switch self {
      case .active(var active):
        var subchannelsToClose = [Subchannel]()

        for (id, subchannelState) in active.subchannels {
          subchannelsToClose.append(subchannelState.subchannel)
          active.parkedSubchannels[id] = subchannelState.subchannel
        }

        if subchannelsToClose.isEmpty {
          self = .closed
          return .closed
        } else {
          self = .closing(Closing(reason: .user, parkedSubchannels: active.parkedSubchannels))
          return .closeSubchannels(subchannelsToClose)
        }

      case .closing, .closed:
        return .none
      }
    }

    enum OnPickSubchannel {
      case picked(Subchannel)
      case notAvailable([Subchannel])
    }

    mutating func pickSubchannel() -> OnPickSubchannel {
      let onMakeStream: OnPickSubchannel

      switch self {
      case .active(var active):
        if let subchannel = active.pick() {
          onMakeStream = .picked(subchannel)
        } else {
          switch active.aggregateConnectivityState {
          case .idle:
            onMakeStream = .notAvailable(active.subchannels.values.map { $0.subchannel })
          case .connecting, .ready, .transientFailure, .shutdown:
            onMakeStream = .notAvailable([])
          }
        }
        self = .active(active)

      case .closing, .closed:
        onMakeStream = .notAvailable([])
      }

      return onMakeStream
    }
  }
}

extension ConnectivityState {
  static func aggregate(_ states: some Collection<ConnectivityState>) -> ConnectivityState {
    // See https://github.com/grpc/grpc/blob/master/doc/load-balancing.md

    // If any one subchannel is in READY state, the channel's state is READY.
    if states.contains(where: { $0 == .ready }) {
      return .ready
    }

    // Otherwise, if there is any subchannel in state CONNECTING, the channel's state is CONNECTING.
    if states.contains(where: { $0 == .connecting }) {
      return .connecting
    }

    // Otherwise, if there is any subchannel in state IDLE, the channel's state is IDLE.
    if states.contains(where: { $0 == .idle }) {
      return .idle
    }

    // Otherwise, if all subchannels are in state TRANSIENT_FAILURE, the channel's state
    //   is TRANSIENT_FAILURE.
    if states.allSatisfy({ $0 == .transientFailure }) {
      return .transientFailure
    }

    return .shutdown
  }
}
