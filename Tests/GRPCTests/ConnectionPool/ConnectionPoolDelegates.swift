/*
 * Copyright 2022, gRPC Authors All rights reserved.
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
import GRPC
import NIOConcurrencyHelpers
import NIOCore

final class IsConnectingDelegate: GRPCConnectionPoolDelegate {
  private let lock = NIOLock()
  private var connecting = Set<GRPCConnectionID>()
  private var active = Set<GRPCConnectionID>()

  enum StateNotifacation: Hashable, Sendable {
    case connecting
    case connected
  }

  private let onStateChange: @Sendable (StateNotifacation) -> Void

  init(onStateChange: @escaping @Sendable (StateNotifacation) -> Void) {
    self.onStateChange = onStateChange
  }

  func startedConnecting(id: GRPCConnectionID) {
    let didStartConnecting: Bool = self.lock.withLock {
      let (inserted, _) = self.connecting.insert(id)
      // Only intereseted new connection attempts when there are no active connections.
      return inserted && self.connecting.count == 1 && self.active.isEmpty
    }

    if didStartConnecting {
      self.onStateChange(.connecting)
    }
  }

  func connectSucceeded(id: GRPCConnectionID, streamCapacity: Int) {
    let didStopConnecting: Bool = self.lock.withLock {
      let removed = self.connecting.remove(id) != nil
      let (inserted, _) = self.active.insert(id)
      return removed && inserted && self.active.count == 1
    }

    if didStopConnecting {
      self.onStateChange(.connected)
    }
  }

  func connectionClosed(id: GRPCConnectionID, error: Error?) {
    self.lock.withLock {
      self.active.remove(id)
      self.connecting.remove(id)
    }
  }

  func connectionQuiescing(id: GRPCConnectionID) {
    self.lock.withLock {
      _ = self.active.remove(id)
    }
  }

  // No-op.
  func connectionAdded(id: GRPCConnectionID) {}

  // No-op.
  func connectionRemoved(id: GRPCConnectionID) {}

  // Conection failures put the connection into a backing off state, we consider that to still
  // be 'connecting' at this point.
  func connectFailed(id: GRPCConnectionID, error: Error) {}

  // No-op.
  func connectionUtilizationChanged(id: GRPCConnectionID, streamsUsed: Int, streamCapacity: Int) {}
}

extension IsConnectingDelegate: @unchecked Sendable {}

final class EventRecordingConnectionPoolDelegate: GRPCConnectionPoolDelegate {
  struct UnexpectedEvent: Error {
    var event: Event

    init(_ event: Event) {
      self.event = event
    }
  }

  enum Event: Equatable {
    case connectionAdded(GRPCConnectionID)
    case startedConnecting(GRPCConnectionID)
    case connectFailed(GRPCConnectionID)
    case connectSucceeded(GRPCConnectionID, Int)
    case connectionClosed(GRPCConnectionID)
    case connectionUtilizationChanged(GRPCConnectionID, Int, Int)
    case connectionQuiescing(GRPCConnectionID)
    case connectionRemoved(GRPCConnectionID)

    var id: GRPCConnectionID {
      switch self {
      case let .connectionAdded(id),
           let .startedConnecting(id),
           let .connectFailed(id),
           let .connectSucceeded(id, _),
           let .connectionClosed(id),
           let .connectionUtilizationChanged(id, _, _),
           let .connectionQuiescing(id),
           let .connectionRemoved(id):
        return id
      }
    }
  }

  private var events: CircularBuffer<Event> = []
  private let lock = NIOLock()

  var first: Event? {
    return self.lock.withLock {
      self.events.first
    }
  }

  var isEmpty: Bool {
    return self.lock.withLock { self.events.isEmpty }
  }

  func popFirst() -> Event? {
    return self.lock.withLock {
      self.events.popFirst()
    }
  }

  func connectionAdded(id: GRPCConnectionID) {
    self.lock.withLock {
      self.events.append(.connectionAdded(id))
    }
  }

  func startedConnecting(id: GRPCConnectionID) {
    self.lock.withLock {
      self.events.append(.startedConnecting(id))
    }
  }

  func connectFailed(id: GRPCConnectionID, error: Error) {
    self.lock.withLock {
      self.events.append(.connectFailed(id))
    }
  }

  func connectSucceeded(id: GRPCConnectionID, streamCapacity: Int) {
    self.lock.withLock {
      self.events.append(.connectSucceeded(id, streamCapacity))
    }
  }

  func connectionClosed(id: GRPCConnectionID, error: Error?) {
    self.lock.withLock {
      self.events.append(.connectionClosed(id))
    }
  }

  func connectionUtilizationChanged(id: GRPCConnectionID, streamsUsed: Int, streamCapacity: Int) {
    self.lock.withLock {
      self.events.append(.connectionUtilizationChanged(id, streamsUsed, streamCapacity))
    }
  }

  func connectionQuiescing(id: GRPCConnectionID) {
    self.lock.withLock {
      self.events.append(.connectionQuiescing(id))
    }
  }

  func connectionRemoved(id: GRPCConnectionID) {
    self.lock.withLock {
      self.events.append(.connectionRemoved(id))
    }
  }
}

extension EventRecordingConnectionPoolDelegate: @unchecked Sendable {}
