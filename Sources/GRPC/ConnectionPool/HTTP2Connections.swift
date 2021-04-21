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

internal struct HTTP2Connections {
  // TODO: The number of connections is likely to be low and insertions and deletions should be
  // infrequent. We may benefit from using an array and doing linear scans instead.
  private var connections: [ObjectIdentifier: HTTP2ConnectionState]

  /// Returns the number of connections.
  internal var count: Int {
    return self.connections.count
  }

  /// The maximum number of connections which may be stored.
  private let capacity: Int

  internal init(capacity: Int) {
    self.connections = [:]
    self.capacity = capacity
    self.connections.reserveCapacity(capacity)
  }

  /// Insert a connection.
  ///
  /// - Important: A connection with the same `id` must not already exist in the collection, and
  ///     a connection may only be inserted if the number of connections is less than its capacity.
  /// - Parameter connection: The connection state to add.
  internal mutating func insert(_ connection: HTTP2ConnectionState) {
    assert(self.count < self.capacity)
    let oldValue = self.connections.updateValue(connection, forKey: connection.id)
    precondition(oldValue == nil)
  }

  /// Remove a connection with the given ID.
  ///
  /// - Parameter id: The ID of the connection to remove.
  /// - Returns: The connection, if one matching the given ID was returned.
  @discardableResult
  internal mutating func removeConnection(withID id: ObjectIdentifier) -> HTTP2ConnectionState? {
    return self.connections.removeValue(forKey: id)
  }

  /// Remove all connections
  internal mutating func removeAll() {
    self.connections.removeAll()
  }

  /// Returns the ID of the first connection matching the predicate, if one exists.
  internal func firstConnectionID(
    where predicate: (HTTP2ConnectionState) -> Bool
  ) -> ObjectIdentifier? {
    return self.connections.first { _, value in
      predicate(value)
    }?.key
  }

  // MARK: - Tokens

  /// Returns the number of tokens available for the connection with the given ID.
  ///
  /// Only active connections may have tokens available, idle connections or those actively
  /// connecting have zero tokens available.
  ///
  /// - Parameter id: The ID of the connection to return the number of available tokens for.
  /// - Returns: The number of tokens available for the connection identified by the given `id`
  ///     or `nil` if no such connection exists.
  internal func availableTokensForConnection(withID id: ObjectIdentifier) -> Int? {
    return self.connections[id]?.availableTokens
  }

  /// Borrow tokens from the connection identified by `id`.
  ///
  /// - Precondition: A connection must exist with the given `id`.
  /// - Precondition: `count` must be greater than zero and must not exceed the tokens available for
  ///     the connection.
  /// - Parameters:
  ///   - count: The number of tokens to borrow.
  ///   - id: The `id` of the connection to borrow tokens from.
  /// - Returns: The connection's HTTP/2 multiplexer and the total number of tokens currently
  ///    borrowed from the connection.
  internal mutating func borrowTokens(
    _ count: Int,
    fromConnectionWithID id: ObjectIdentifier
  ) -> (HTTP2StreamMultiplexer, borrowedTokens: Int) {
    return self.connections[id]!.borrowTokens(count)
  }

  /// Return a single token to the connection with the given identifier.
  ///
  /// - Parameter id: The `id` of the connection to return a token to.
  internal mutating func returnTokenToConnection(withID id: ObjectIdentifier) {
    self.connections[id]?.returnToken()
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
    return self.connections[id]?.updateMaximumTokens(maximumTokens)
  }

  /// Start connecting the connection with the given `id`.
  ///
  /// - Parameters:
  ///   - id: The `id` of the connection to start.
  ///   - multiplexerFactory: A closure which returns an `EventLoopFuture<HTTP2StreamMultiplexer>`.
  ///   - onConnected: A closure to execute when the connection has successfully been established.
  internal mutating func startConnection(
    withID id: ObjectIdentifier,
    http2StreamMultiplexerFactory multiplexerFactory: () -> EventLoopFuture<HTTP2StreamMultiplexer>,
    whenConnected onConnected: @escaping (HTTP2StreamMultiplexer) -> Void
  ) {
    self.connections[id]?.willStartConnecting()
    multiplexerFactory().whenSuccess(onConnected)
  }

  /// Update the state of the connection identified by `id` to 'ready'.
  internal mutating func connectionIsReady(
    withID id: ObjectIdentifier,
    multiplexer: HTTP2StreamMultiplexer
  ) {
    self.connections[id]?.connected(multiplexer: multiplexer)
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
    return self.connections[id]?.connectivityStateChanged(to: state)
  }
}
