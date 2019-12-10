/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
import NIOConcurrencyHelpers
import Logging

/// The connectivity state of a client connection. Note that this is heavily lifted from the gRPC
/// documentation: https://github.com/grpc/grpc/blob/master/doc/connectivity-semantics-and-api.md.
public enum ConnectivityState {
  /// This is the state where the channel has not yet been created.
  case idle

  /// The channel is trying to establish a connection and is waiting to make progress on one of the
  /// steps involved in name resolution, TCP connection establishment or TLS handshake.
  case connecting

  /// The channel has successfully established a connection all the way through TLS handshake (or
  /// equivalent) and protocol-level (HTTP/2, etc) handshaking.
  case ready

  /// There has been some transient failure (such as a TCP 3-way handshake timing out or a socket
  /// error). Channels in this state will eventually switch to the `.connecting` state and try to
  /// establish a connection again. Since retries are done with exponential backoff, channels that
  /// fail to connect will start out spending very little time in this state but as the attempts
  /// fail repeatedly, the channel will spend increasingly large amounts of time in this state.
  case transientFailure

  /// This channel has started shutting down. Any new RPCs should fail immediately. Pending RPCs
  /// may continue running till the application cancels them. Channels may enter this state either
  /// because the application explicitly requested a shutdown or if a non-recoverable error has
  /// happened during attempts to connect. Channels that have entered this state will never leave
  /// this state.
  case shutdown
}

public protocol ConnectivityStateDelegate: class {
  /// Called when a change in `ConnectivityState` has occurred.
  ///
  /// - Parameter oldState: The old connectivity state.
  /// - Parameter newState: The new connectivity state.
  func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState)
}

public class ConnectivityStateMonitor {
  private let logger = Logger(subsystem: .connectivityState)
  private let lock = Lock()
  private var _state: ConnectivityState = .idle
  private var _userInitiatedShutdown = false
  private var _delegate: ConnectivityStateDelegate?

  /// Creates a new connectivity state monitor.
  ///
  /// - Parameter delegate: A delegate to call when the connectivity state changes.
  public init(delegate: ConnectivityStateDelegate?) {
    self._delegate = delegate
  }

  /// The current state of connectivity.
  public internal(set) var state: ConnectivityState {
    get {
      return self.lock.withLock {
        self._state
      }
    }
    set {
      self.lock.withLockVoid {
        self.setNewState(to: newValue)
      }
    }
  }

  /// A delegate to call when the connectivity state changes.
  public var delegate: ConnectivityStateDelegate? {
    get {
      return self.lock.withLock {
        return self._delegate
      }
    }
    set {
      self.lock.withLockVoid {
        self._delegate = newValue
      }
    }
  }

  /// Updates `_state` to `newValue`.
  ///
  /// If the user has initiated shutdown then state updates are _ignored_. This may happen if the
  /// connection is being established as the user initiates shutdown.
  ///
  /// - Important: This is **not** thread safe.
  private func setNewState(to newValue: ConnectivityState) {
    if self._userInitiatedShutdown {
      self.logger.debug("user has initiated shutdown: ignoring new state: \(newValue)")
      return
    }

    let oldValue = self._state
    if oldValue != newValue {
      self.logger.debug("connectivity state change: \(oldValue) to \(newValue)")
      self._state = newValue
      self._delegate?.connectivityStateDidChange(from: oldValue, to: newValue)
    }
  }

  /// Initiates a user shutdown.
  func initiateUserShutdown() {
    self.lock.withLockVoid {
      self.logger.debug("user has initiated shutdown")
      self.setNewState(to: .shutdown)
      self._userInitiatedShutdown = true
    }
  }

  /// Whether the user has initiated a shutdown or not.
  var userHasInitiatedShutdown: Bool {
    return self.lock.withLock {
      return self._userInitiatedShutdown
    }
  }

  /// Whether we can attempt a reconnection, that is the user has not initiated a shutdown and we
  /// are in the `.ready` state.
  var canAttemptReconnect: Bool {
    return self.lock.withLock {
      return !self._userInitiatedShutdown && self._state == .ready
    }
  }
}
