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
import NIO
import NIOHTTP2

/// `ManagedHTTP2Connections` provides a `ConnectionManager` for each connection state in
/// `HTTP2Connections`.
///
/// Most of the API is identical to - and calls through to - an underlying `HTTP2Connection`.
internal struct ManagedHTTP2Connections {
  // TODO: The number of connections is likely to be low and insertions and deletions should be
  // infrequent. We may benefit from using an array and doing linear scans instead hashing the
  // identifier.
  private var managers: [ObjectIdentifier: ConnectionManager]
  private var connections: HTTP2Connections

  /// Returns the number of connections.
  internal var count: Int {
    return self.managers.count
  }

  /// Returns the number of idle connections.
  internal var idleCount: Int {
    return self.connections.idleCount
  }

  /// Returns the number of ready connections.
  internal var readyCount: Int {
    return self.connections.readyCount
  }

  /// Returns the number of connections which are connecting or backing off before another
  /// connection attempt.
  internal var connectingCount: Int {
    return self.connections.connectingCount
  }

  /// Returns then capacity of the pool.
  private let capacity: Int

  internal init(capacity: Int) {
    self.capacity = capacity
    self.connections = HTTP2Connections(capacity: capacity)
    self.managers = [:]
    self.managers.reserveCapacity(capacity)
  }

  internal mutating func insertConnection(
    _ manager: ConnectionManager,
    withID id: ObjectIdentifier
  ) {
    self.connections.insert(HTTP2ConnectionState(connectionManagerID: id))
    self.managers[id] = manager
    assert(self.connections.count == self.managers.count)
  }

  internal mutating func removeConnection(
    withID id: ObjectIdentifier
  ) -> ConnectionManager? {
    defer {
      assert(self.connections.count == self.managers.count)
    }
    self.connections.removeConnection(withID: id)
    return self.managers.removeValue(forKey: id)
  }

  internal mutating func removeAll() -> [ConnectionManager] {
    let connectionManagers = Array(self.managers.values)
    self.managers.removeAll()
    self.connections.removeAll()
    return connectionManagers
  }

  // MARK: - Connection Lifecycle

  internal func eventLoopForConnection(withID id: ObjectIdentifier) -> EventLoop? {
    return self.managers[id]?.eventLoop
  }

  internal func firstIdleConnectionID() -> ObjectIdentifier? {
    return self.connections.firstConnectionID(where: { $0.isIdle })
  }

  internal mutating func startConnection(
    withID id: ObjectIdentifier,
    whenConnected onConnected: @escaping (HTTP2StreamMultiplexer) -> Void
  ) {
    if let manager = self.managers[id] {
      self.connections.startConnection(
        withID: id,
        http2StreamMultiplexerFactory: manager.getHTTP2Multiplexer,
        whenConnected: onConnected
      )
    }
  }

  internal mutating func connectionIsReady(
    withID id: ObjectIdentifier,
    multiplexer: HTTP2StreamMultiplexer
  ) {
    self.connections.connectionIsReady(withID: id, multiplexer: multiplexer)
  }

  /// Update connectivity state of the connection identified by `id`.
  ///
  /// - Parameters:
  ///   - state: The new state of the underlying connection.
  ///   - id: The `id` of the connection whose state has changed.
  /// - Returns: An action to perform as a result of the state change.
  internal mutating func updateConnectivityState(
    _ state: ConnectivityState,
    forConnectionWithID id: ObjectIdentifier
  ) -> HTTP2ConnectionState.StateChangeAction? {
    return self.connections.updateConnectivityState(state, forConnectionWithID: id)
  }

  /// The total number of available tokens across all connections.
  internal var availableTokens: Int {
    return self.connections.availableTokens
  }

  /// Borrow tokens from the connection identified by `id`.
  ///
  /// - Parameters:
  ///   - count: The number of tokens to borrow.
  ///   - id: The `id` of the connection to borrow tokens from.
  /// - Returns: The borrowed HTTP/2 multiplexer and the number of tokens which were borrowed (which
  ///    may be less than `count`) and the total number of tokens which are currently being
  ///    borrowed. Returns `nil` if no connection with identified by `id` exists or there are no
  ///    available tokens on that connection.
  internal mutating func borrowTokens(
    _ count: Int,
    fromConnectionWithID id: ObjectIdentifier
  ) -> HTTP2ConnectionState.BorrowedTokens? {
    return self.connections.borrowTokens(count, fromConnectionWithID: id)
  }

  /// Borrow a single token from the connection with the given `id`.
  ///
  /// See also: `borrowTokens(_:fromConnectionWithID)`.
  internal mutating func borrowTokenFromConnection(
    withID id: ObjectIdentifier
  ) -> HTTP2ConnectionState.BorrowedTokens? {
    return self.borrowTokens(1, fromConnectionWithID: id)
  }

  /// The total number of borrowed tokens over all connections.
  internal var borrowedTokens: Int {
    return self.connections.borrowedTokens
  }

  /// Return a single token to the connection with the given identifier.
  ///
  /// - Parameter id: The `id` of the connection to return a token to.
  internal mutating func returnTokenToConnection(withID id: ObjectIdentifier) {
    self.connections.returnTokenToConnection(withID: id)
  }

  /// Update the maximum number of tokens a connection may lend at a given time.
  ///
  /// - Parameters:
  ///   - maximumTokens: The maximum number of tokens the connection may vend,
  ///   - id: The `id` of the connection the new limit applies to.
  /// - Returns: The previous maximum token limit if the connection exists.
  internal mutating func updateMaximumAvailableTokens(
    _ maximumTokens: Int,
    forConnectionWithID id: ObjectIdentifier
  ) -> Int? {
    return self.connections.updateMaximumAvailableTokens(maximumTokens, forConnectionWithID: id)
  }

  // MARK: - Token Borrowing

  /// Returns the identifier of the connection on the given `EventLoop` with the most available
  /// tokens.
  ///
  /// - Parameter eventLoop: The `EventLoop` the connection must be on.
  /// - Returns: The ID of the connection with the most available tokens on the given event loop.
  internal func connectionIDWithMostAvailableTokens(on eventLoop: EventLoop) -> ObjectIdentifier? {
    var mostAvailable = 0
    var mostAvailableID: ObjectIdentifier?

    for (id, manager) in self.managers where manager.eventLoop === eventLoop {
      let availableTokens = self.connections.availableTokensForConnection(withID: id)!
      if availableTokens > mostAvailable {
        mostAvailable = availableTokens
        mostAvailableID = id
      }
    }

    return mostAvailableID
  }

  struct BorrowedToken {
    /// The multiplexer to borrow a stream from.
    var multiplexer: HTTP2StreamMultiplexer
    /// The `EventLoop` of the `Channel` the `multiplexer` is on.
    var eventLoop: EventLoop
    /// The total number of tokens borrowed from the connection.
    var totalBorrowCount: Int
    /// The ID of the connection.
    var id: ObjectIdentifier
  }

  /// Borrow a single token from the connection with the most available tokens.
  ///
  /// If a preferred event loop is specified then the connection with the most tokens available
  /// using that event loop is used. If no connection using that event loop has tokens available
  /// then the preference is ignored.
  ///
  /// - Parameter preferredEventLoop: The preferred `EventLoop` of the connection to borrow from.
  internal mutating func borrowTokenFromConnectionWithMostAvailable(
    preferredEventLoop: EventLoop?
  ) -> BorrowedToken? {
    guard let candidate = self.connectionWithMostAvailableTokens(
      preferredEventLoop: preferredEventLoop
    ) else {
      return nil
    }

    guard let borrowed = self.connections.borrowTokens(1, fromConnectionWithID: candidate.id) else {
      return nil
    }

    return BorrowedToken(
      multiplexer: borrowed.multiplexer,
      eventLoop: candidate.eventLoop,
      totalBorrowCount: borrowed.totalBorrowCount,
      id: candidate.id
    )
  }

  private struct CandidateConnection {
    var id: ObjectIdentifier
    var availableTokens: Int
    var eventLoop: EventLoop
    var isPreferredEventLoop: Bool

    mutating func update(
      id: ObjectIdentifier,
      availableTokens: Int,
      eventLoop: EventLoop,
      isPreferred: Bool
    ) {
      if self.isPreferredEventLoop {
        // Already on the preferred event loop, only update if there are more tokens available.
        if availableTokens > self.availableTokens {
          self.availableTokens = availableTokens
          self.id = id
        } else {
          // The current candidate is better.
        }
      } else if isPreferred {
        // We're not on the preferred event loop, but we are now.
        self.availableTokens = availableTokens
        self.eventLoop = eventLoop
        self.isPreferredEventLoop = true
        self.id = id
      } else if availableTokens > self.availableTokens {
        // We've never seen the preferred event loop.
        self.availableTokens = availableTokens
        self.eventLoop = eventLoop
        self.id = id
      }
    }
  }

  private func connectionWithMostAvailableTokens(
    preferredEventLoop: EventLoop?
  ) -> CandidateConnection? {
    var candidate: CandidateConnection?

    for (id, manager) in self.managers {
      guard let availableTokens = self.connections.availableTokensForConnection(withID: id),
        availableTokens > 0 else {
        // No tokens available, move on.
        continue
      }

      if candidate == nil {
        // This is our candidate now.
        candidate = CandidateConnection(
          id: id,
          availableTokens: availableTokens,
          eventLoop: manager.eventLoop,
          isPreferredEventLoop: manager.eventLoop === preferredEventLoop
        )
      } else {
        // Update the candidate.
        candidate!.update(
          id: id,
          availableTokens: availableTokens,
          eventLoop: manager.eventLoop,
          isPreferred: manager.eventLoop === preferredEventLoop
        )
      }
    }

    return candidate
  }

  /// Returns the identifier of the connection with the most available tokens.
  /// - Returns: The identified of the connection with the most available tokens, if one exists.
  internal func connectionIDWithMostAvailableTokens() -> ObjectIdentifier? {
    var mostAvailable = 0
    var mostAvailableID: ObjectIdentifier?

    for id in self.managers.keys {
      let availableTokens = self.connections.availableTokensForConnection(withID: id)!
      if availableTokens > mostAvailable {
        mostAvailable = availableTokens
        mostAvailableID = id
      }
    }

    return mostAvailableID
  }
}
