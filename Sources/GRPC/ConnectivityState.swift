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
import Logging
import NIOConcurrencyHelpers
import NIOCore

/// The connectivity state of a client connection. Note that this is heavily lifted from the gRPC
/// documentation: https://github.com/grpc/grpc/blob/master/doc/connectivity-semantics-and-api.md.
public enum ConnectivityState: GRPCSendable {
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

public protocol ConnectivityStateDelegate: AnyObject, GRPCSendable {
  /// Called when a change in `ConnectivityState` has occurred.
  ///
  /// - Parameter oldState: The old connectivity state.
  /// - Parameter newState: The new connectivity state.
  func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState)

  /// Called when the connection has started quiescing, that is, the connection is going away but
  /// existing RPCs may continue to run.
  ///
  /// - Important: When this is called no new RPCs may be created until the connectivity state
  ///   changes to 'idle' (the connection successfully quiesced) or 'transientFailure' (the
  ///   connection was closed before quiescing completed). Starting RPCs before these state changes
  ///   will lead to a connection error and the immediate failure of any outstanding RPCs.
  func connectionStartedQuiescing()
}

extension ConnectivityStateDelegate {
  public func connectionStartedQuiescing() {}
}

#if compiler(>=5.6)
// Unchecked because all mutable state is protected by locks.
extension ConnectivityStateMonitor: @unchecked Sendable {}
#endif // compiler(>=5.6)

public class ConnectivityStateMonitor {
  private let stateLock = Lock()
  private var _state: ConnectivityState = .idle

  private let delegateLock = Lock()
  private var _delegate: ConnectivityStateDelegate?
  private let delegateCallbackQueue: DispatchQueue

  /// Creates a new connectivity state monitor.
  ///
  /// - Parameter delegate: A delegate to call when the connectivity state changes.
  /// - Parameter queue: The `DispatchQueue` on which the delegate will be called.
  init(delegate: ConnectivityStateDelegate?, queue: DispatchQueue?) {
    self._delegate = delegate
    self.delegateCallbackQueue = DispatchQueue(label: "io.grpc.connectivity", target: queue)
  }

  /// The current state of connectivity.
  public var state: ConnectivityState {
    return self.stateLock.withLock {
      self._state
    }
  }

  /// A delegate to call when the connectivity state changes.
  public var delegate: ConnectivityStateDelegate? {
    get {
      return self.delegateLock.withLock {
        return self._delegate
      }
    }
    set {
      self.delegateLock.withLockVoid {
        self._delegate = newValue
      }
    }
  }

  internal func updateState(to newValue: ConnectivityState, logger: Logger) {
    let change: (ConnectivityState, ConnectivityState)? = self.stateLock.withLock {
      let oldValue = self._state

      if oldValue != newValue {
        self._state = newValue
        return (oldValue, newValue)
      } else {
        return nil
      }
    }

    if let (oldState, newState) = change {
      logger.debug("connectivity state change", metadata: [
        "old_state": "\(oldState)",
        "new_state": "\(newState)",
      ])

      self.delegateCallbackQueue.async {
        if let delegate = self.delegate {
          delegate.connectivityStateDidChange(from: oldState, to: newState)
        }
      }
    }
  }

  internal func beginQuiescing() {
    self.delegateCallbackQueue.async {
      if let delegate = self.delegate {
        delegate.connectionStartedQuiescing()
      }
    }
  }
}

extension ConnectivityStateMonitor: ConnectionManagerConnectivityDelegate {
  internal func connectionStateDidChange(
    _ connectionManager: ConnectionManager,
    from oldState: _ConnectivityState,
    to newState: _ConnectivityState
  ) {
    self.updateState(to: ConnectivityState(newState), logger: connectionManager.logger)
  }

  internal func connectionIsQuiescing(_ connectionManager: ConnectionManager) {
    self.beginQuiescing()
  }
}
