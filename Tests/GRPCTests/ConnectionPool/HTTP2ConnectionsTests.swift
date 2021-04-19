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
@testable import GRPC
import Logging
import NIO
import NIOHTTP2
import XCTest

final class HTTP2ConnectionsTests: GRPCTestCase {
  private final class Placeholder {}
  private var placeholders: [Placeholder] = []

  private let eventLoop = EmbeddedEventLoop()

  override func setUp() {
    super.setUp()
  }

  private func makeID() -> ObjectIdentifier {
    let placeholder = Placeholder()
    self.placeholders.append(placeholder)
    return ObjectIdentifier(placeholder)
  }

  private func makeConnectionState(withID id: ObjectIdentifier) -> HTTP2ConnectionState {
    return HTTP2ConnectionState(connectionManagerID: id)
  }

  func testEmpty() {
    var connections = HTTP2Connections(capacity: 5)
    XCTAssertEqual(connections.count, 0)

    XCTAssertNil(connections.availableTokensForConnection(withID: self.makeID()))
    XCTAssertNil(connections.firstConnectionID(where: { _ in true }))
    XCTAssertNil(connections.removeConnection(withID: self.makeID()))
    XCTAssertNil(connections.updateConnectivityState(.shutdown, forConnectionWithID: self.makeID()))
    XCTAssertNil(
      connections.updateMaximumAvailableTokens(
        .max,
        forConnectionWithID: self.makeID()
      )
    )
  }

  func testInsertAndRemove() {
    var connections = HTTP2Connections(capacity: 8)
    let connection1 = self.makeConnectionState(withID: self.makeID())
    let connection2 = self.makeConnectionState(withID: self.makeID())

    connections.insert(connection1)
    XCTAssertEqual(connections.count, 1)

    connections.insert(connection2)
    XCTAssertEqual(connections.count, 2)

    let removed = connections.removeConnection(withID: connection1.id)
    XCTAssertEqual(connections.count, 1)
    XCTAssertEqual(removed?.id, connection1.id)

    connections.insert(connection1)
    XCTAssertEqual(connections.count, 2)

    connections.removeAll()
    XCTAssertEqual(connections.count, 0)
  }

  func testFirstConnectionIDWhere() {
    var connections = HTTP2Connections(capacity: 8)
    let connection1 = self.makeConnectionState(withID: self.makeID())
    connections.insert(connection1)
    let connection2 = self.makeConnectionState(withID: self.makeID())
    connections.insert(connection2)

    XCTAssertNil(connections.firstConnectionID(where: { _ in false }))
    XCTAssertNil(connections.firstConnectionID(where: { $0.id == self.makeID() }))
    XCTAssertEqual(
      connections.firstConnectionID(where: { $0.id == connection1.id }),
      connection1.id
    )
    XCTAssertNotNil(connections.firstConnectionID(where: { $0.isIdle }))
  }

  func testSetupBorrowAndReturn() throws {
    var connections = HTTP2Connections(capacity: 8)
    let connection = self.makeConnectionState(withID: self.makeID())
    connections.insert(connection)

    var multiplexers: [HTTP2StreamMultiplexer] = []
    connections.startConnection(
      withID: connection.id,
      http2StreamMultiplexerFactory: {
        let multiplexer = HTTP2StreamMultiplexer(
          mode: .client,
          channel: EmbeddedChannel(loop: self.eventLoop),
          inboundStreamInitializer: nil
        )
        return self.eventLoop.makeSucceededFuture(multiplexer)
      },
      whenConnected: {
        multiplexers.append($0)
      }
    )

    // We have an embedded event loop, so we should already have a multiplexer and we can tell
    // the connections about it.
    XCTAssertEqual(multiplexers.count, 1)
    connections.connectionIsReady(withID: connection.id, multiplexer: multiplexers[0])

    // 100 is the default.
    XCTAssertEqual(connections.availableTokensForConnection(withID: connection.id), 100)

    // Borrow a token.
    let (mux, borrowed) = connections.borrowTokens(1, fromConnectionWithID: connection.id)
    // 1 token has been borrowed in total.
    XCTAssertEqual(borrowed, 1)
    XCTAssertTrue(mux === multiplexers[0])
    XCTAssertEqual(connections.availableTokensForConnection(withID: connection.id), 99)

    // Return a token.
    connections.returnTokenToConnection(withID: connection.id)
    XCTAssertEqual(connections.availableTokensForConnection(withID: connection.id), 100)
  }
}
