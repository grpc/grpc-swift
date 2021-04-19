/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import Logging
import NIO
import NIOHTTP2

/// This struct models the state of an HTTP/2 connection and provides the means to indirectly track
/// active and available HTTP/2 streams on that connection.
///
/// The state -- once ready -- holds a multiplexer which it yields when an available 'token' is
/// borrowed. One token corresponds to the creation of one HTTP/2 stream. The caller is responsible
/// for later returning the token.
internal struct HTTP2ConnectionState {
  /// An identifier for this pooled connection.
  internal let id: ObjectIdentifier

  /// Indicates whether the pooled connection is idle.
  internal var isIdle: Bool {
    return self.state.isIdle
  }

  /// The number of tokens currently available for this connection. `availableTokens` must be
  /// greater than zero for `borrowTokens` to be called.
  ///
  /// Note that it is also possible for `availableTokens` to be negative.
  internal var availableTokens: Int {
    switch self.state {
    case let .ready(ready):
      return ready.availableTokens
    case .idle, .connectingOrBackingOff:
      return 0
    }
  }

  /// The number of tokens currently borrowed from this connection.
  internal var borrowedTokens: Int {
    switch self.state {
    case let .ready(ready):
      return ready.borrowedTokens
    case .idle, .connectingOrBackingOff:
      return 0
    }
  }

  /// The state of the pooled connection.
  private var state: State

  private enum State {
    /// No connection has been asked for, there are no tokens available.
    case idle

    /// A connection attempt is underway or we may be waiting to attempt to connect again.
    case connectingOrBackingOff

    /// We have an active connection which may have tokens borrowed.
    case ready(ReadyState)

    /// Whether the state is `idle`.
    var isIdle: Bool {
      switch self {
      case .idle:
        return true
      case .connectingOrBackingOff, .ready:
        return false
      }
    }
  }

  private struct ReadyState {
    internal var multiplexer: HTTP2StreamMultiplexer
    internal var borrowedTokens: Int
    internal var tokenLimit: Int

    internal init(multiplexer: HTTP2StreamMultiplexer) {
      self.multiplexer = multiplexer
      self.borrowedTokens = 0
      // 100 is a common value for HTTP/2 SETTINGS_MAX_CONCURRENT_STREAMS so we assume this value
      // until we know better.
      self.tokenLimit = 100
    }

    internal var availableTokens: Int {
      return self.tokenLimit - self.borrowedTokens
    }

    internal mutating func borrowTokens(_ count: Int) -> (HTTP2StreamMultiplexer, Int) {
      self.borrowedTokens += count
      assert(self.borrowedTokens <= self.tokenLimit)
      return (self.multiplexer, self.borrowedTokens)
    }

    internal mutating func returnToken() {
      self.borrowedTokens -= 1
      assert(self.borrowedTokens >= 0)
    }

    internal mutating func updateTokenLimit(_ limit: Int) -> Int {
      let oldLimit = self.tokenLimit
      self.tokenLimit = limit
      return oldLimit
    }
  }

  internal init(connectionManagerID: ObjectIdentifier) {
    self.id = connectionManagerID
    self.state = .idle
  }

  // MARK: - Lease Management

  /// Borrow tokens from the pooled connection.
  ///
  /// Each borrowed token corresponds to the creation of one HTTP/2 stream using the multiplexer
  /// returned from this call. The caller must return each token once the stream is no longer
  /// required using `returnToken(multiplexerID:)` where `multiplexerID` is the `ObjectIdentifier`
  /// for the `HTTP2StreamMultiplexer` returned from this call.
  ///
  /// - Parameter tokensToBorrow: The number of tokens to borrow. This *must not*
  ///     exceed `availableTokens`.
  /// - Returns: A tuple of the `HTTP2StreamMultiplexer` on which streams should be created and
  ///     total number of tokens which have been borrowed from this connection.
  mutating func borrowTokens(_ tokensToBorrow: Int) -> (HTTP2StreamMultiplexer, Int) {
    switch self.state {
    case var .ready(ready):
      let result = ready.borrowTokens(tokensToBorrow)
      self.state = .ready(ready)
      return result

    case .idle, .connectingOrBackingOff:
      // `availableTokens` is zero for these two states and a precondition for calling this function
      // is that `tokensToBorrow` must not exceed the available tokens.
      preconditionFailure()
    }
  }

  /// Return a single token to the pooled connection.
  mutating func returnToken() {
    switch self.state {
    case var .ready(ready):
      ready.returnToken()
      self.state = .ready(ready)

    case .idle, .connectingOrBackingOff:
      // A token may have been returned after the connection dropped.
      ()
    }
  }

  /// Updates the maximum number of tokens a connection may vend at any given time and returns the
  /// previous limit.
  ///
  /// If the new limit is higher than the old limit then there may now be some tokens available
  /// (i.e. `availableTokens > 0`). If the new limit is lower than the old limit `availableTokens`
  /// will decrease and this connection may not have any available tokens.
  ///
  /// - Parameters:
  ///   - newValue: The maximum number of tokens a connection may vend at a given time.
  /// - Returns: The previous token limit.
  mutating func updateMaximumTokens(_ newValue: Int) -> Int {
    switch self.state {
    case var .ready(ready):
      let oldLimit = ready.updateTokenLimit(newValue)
      self.state = .ready(ready)
      return oldLimit

    case .idle, .connectingOrBackingOff:
      preconditionFailure()
    }
  }

  /// Notify the state that a connection attempt is about to start.
  mutating func willStartConnecting() {
    switch self.state {
    case .idle, .ready:
      // We can start connecting from the 'ready' state again if the connection was dropped.
      self.state = .connectingOrBackingOff

    case .connectingOrBackingOff:
      preconditionFailure()
    }
  }

  /// The connection attempt succeeded.
  ///
  /// - Parameter multiplexer: The `HTTP2StreamMultiplexer` from the connection.
  mutating func connected(multiplexer: HTTP2StreamMultiplexer) {
    switch self.state {
    case .connectingOrBackingOff:
      self.state = .ready(ReadyState(multiplexer: multiplexer))

    case .idle, .ready:
      preconditionFailure()
    }
  }

  /// Notify the state of a change in connectivity from the guts of the connection (as emitted by
  /// the `ConnectivityStateDelegate`).
  ///
  /// - Parameter state: The new state.
  /// - Returns: Any action to perform as a result of the state change.
  mutating func connectivityStateChanged(to state: ConnectivityState) -> StateChangeAction {
    // We only care about a few transitions as we mostly rely on our own state transitions. Namely,
    // we care about a change from ready to transient failure (as we need to invalidate any borrowed
    // tokens and start a new connection). We also care about shutting down.
    switch (state, self.state) {
    case (.idle, _):
      // We always need to invalidate any state when the channel becomes idle again.
      self.state = .idle
      return .nothing

    case (.connecting, _),
         (.ready, _):
      // We may bounce between 'connecting' and 'transientFailure' when we're in
      // the 'connectingOrBackingOff', it's okay to ignore 'connecting' here.
      //
      // We never pay attention to receiving 'ready', rather we rely on 'connected(multiplexer:)'
      // instead.
      return .nothing

    case (.transientFailure, .ready):
      // If we're ready and hit a transient failure, we must start connecting again. We'll defer our
      // own state transition until 'willStartConnecting()' is called.
      return .startConnectingAgain

    case (.transientFailure, .idle),
         (.transientFailure, .connectingOrBackingOff):
      return .nothing

    case (.shutdown, _):
      // The connection has been shutdown. We shouldn't pay attention to it anymore.
      return .removeFromConnectionList
    }
  }

  internal enum StateChangeAction: Hashable {
    /// Do nothing.
    case nothing
    /// Remove the connection from the pooled connections, it has been shutdown.
    case removeFromConnectionList
    /// Check if any waiters exist for the connection.
    case checkWaiters
    /// The connection dropped: ask for a new one.
    case startConnectingAgain
  }
}
