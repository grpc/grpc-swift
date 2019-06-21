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
  public typealias Callback = () -> Void

  private var idleCallback: Callback?
  private var connectingCallback: Callback?
  private var readyCallback: Callback?
  private var transientFailureCallback: Callback?
  private var shutdownCallback: Callback?

  /// A delegate to call when the connectivity state changes.
  public var delegate: ConnectivityStateDelegate?

  /// The current state of connectivity.
  public internal(set) var state: ConnectivityState {
    didSet {
      if oldValue != self.state {
        self.delegate?.connectivityStateDidChange(from: oldValue, to: self.state)
        self.triggerAndResetCallback()
      }
    }
  }

  /// Creates a new connectivity state monitor.
  ///
  /// - Parameter delegate: A delegate to call when the connectivity state changes.
  public init(delegate: ConnectivityStateDelegate?) {
    self.delegate = delegate
    self.state = .idle
  }

  /// Registers a callback on the given state and calls it the next time that state is observed.
  /// Subsequent transitions to that state will **not** trigger the callback.
  ///
  /// - Parameter state: The state on which to call the given callback.
  /// - Parameter callback: The closure to call once the given state has been transitioned to. The
  ///     `callback` can be removed by passing in `nil`.
  public func onNext(state: ConnectivityState, callback: Callback?) {
    switch state {
    case .idle:
      self.idleCallback = callback

    case .connecting:
      self.connectingCallback = callback

    case .ready:
      self.readyCallback = callback

    case .transientFailure:
      self.transientFailureCallback = callback

    case .shutdown:
      self.shutdownCallback = callback
    }
  }

  private func triggerAndResetCallback() {
    switch self.state {
    case .idle:
      self.idleCallback?()
      self.idleCallback = nil

    case .connecting:
      self.connectingCallback?()
      self.connectingCallback = nil

    case .ready:
      self.readyCallback?()
      self.readyCallback = nil

    case .transientFailure:
      self.transientFailureCallback?()
      self.transientFailureCallback = nil

    case .shutdown:
      self.shutdownCallback?()
      self.shutdownCallback = nil
    }
  }
}
