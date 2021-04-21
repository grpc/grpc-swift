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

final class HTTP2ConnectionStateTests: GRPCTestCase {
  private final class Placeholder {}
  private var placeholders: [Placeholder] = []

  private let channel = EmbeddedChannel()
  private var multiplexer: HTTP2StreamMultiplexer!

  private var eventLoop: EmbeddedEventLoop {
    return self.channel.embeddedEventLoop
  }

  override func setUp() {
    super.setUp()
    self.multiplexer = HTTP2StreamMultiplexer(
      mode: .client,
      channel: self.channel,
      inboundStreamInitializer: nil
    )
  }

  private func makeHTTP2ConnectionState() -> HTTP2ConnectionState {
    let placeholder = Placeholder()
    self.placeholders.append(placeholder)
    return HTTP2ConnectionState(connectionManagerID: ObjectIdentifier(placeholder))
  }

  func testNewPooledConnection() {
    let state = self.makeHTTP2ConnectionState()
    XCTAssertEqual(state.availableTokens, 0)
    XCTAssertEqual(state.borrowedTokens, 0)
    XCTAssert(state.isIdle)
  }

  func testIdleToConnected() {
    var state = self.makeHTTP2ConnectionState()
    state.willStartConnecting()
    XCTAssertEqual(state.availableTokens, 0)
    XCTAssertFalse(state.isIdle)

    state.connected(multiplexer: self.multiplexer)
    // 100 is the default value
    XCTAssertEqual(state.availableTokens, 100)

    let newTokenLimit = 10
    let oldLimit = state.updateMaximumTokens(newTokenLimit)
    XCTAssertEqual(oldLimit, 100)
    XCTAssertEqual(state.availableTokens, newTokenLimit)
  }

  func testBorrowAndReturnTokens() {
    var state = self.makeHTTP2ConnectionState()

    state.willStartConnecting()
    state.connected(multiplexer: self.multiplexer)
    _ = state.updateMaximumTokens(10)

    XCTAssertEqual(state.availableTokens, 10)
    XCTAssertEqual(state.borrowedTokens, 0)

    _ = state.borrowTokens(1)
    XCTAssertEqual(state.borrowedTokens, 1)
    XCTAssertEqual(state.availableTokens, 9)

    _ = state.borrowTokens(9)
    XCTAssertEqual(state.borrowedTokens, 10)
    XCTAssertEqual(state.availableTokens, 0)

    state.returnToken()
    XCTAssertEqual(state.borrowedTokens, 9)
    XCTAssertEqual(state.availableTokens, 1)
  }

  func testConnectivityChanges() {
    var state = self.makeHTTP2ConnectionState()

    XCTAssert(state.isIdle)
    XCTAssertEqual(state.connectivityStateChanged(to: .idle), .nothing)

    state.willStartConnecting()
    XCTAssertFalse(state.isIdle)

    // No changes expected.
    XCTAssertEqual(state.connectivityStateChanged(to: .connecting), .nothing)
    XCTAssertEqual(state.connectivityStateChanged(to: .transientFailure), .nothing)
    XCTAssertEqual(state.connectivityStateChanged(to: .connecting), .nothing)

    // We do nothing on '.ready', instead we wait for '.connected(multiplexer:)' as our signal
    // that we're actually ready (since it provides the 'HTTP2StreamMultiplexer'.
    XCTAssertEqual(state.connectivityStateChanged(to: .ready), .nothing)

    state.connected(multiplexer: self.multiplexer)
    let readyState = state

    // The connection dropped, so the multiplexer we hold is no longer valid, as such we need to ask
    // for a new one.
    XCTAssertEqual(state.connectivityStateChanged(to: .transientFailure), .startConnectingAgain)

    // Restore the connection in the ready state.
    state = readyState

    // Shutdown: we'll drop the connection from the list, it's the end of the road for this
    // connection.
    XCTAssertEqual(state.connectivityStateChanged(to: .shutdown), .removeFromConnectionList)
  }
}
