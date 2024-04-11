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

import NIOCore
import NIOEmbedded
import XCTest

@testable import GRPCHTTP2Core

final class ClientConnectionHandlerStateMachineTests: XCTestCase {
  private func makeStateMachine(
    keepaliveWithoutCalls: Bool = false
  ) -> ClientConnectionHandler.StateMachine {
    return ClientConnectionHandler.StateMachine(allowKeepaliveWithoutCalls: keepaliveWithoutCalls)
  }

  func testCloseSomeStreamsWhenActive() {
    var state = self.makeStateMachine()
    state.streamOpened(1)
    state.streamOpened(2)
    XCTAssertEqual(state.streamClosed(2), .none)
    XCTAssertEqual(state.streamClosed(1), .startIdleTimer(cancelKeepalive: true))
  }

  func testCloseSomeStreamsWhenClosing() {
    var state = self.makeStateMachine()
    state.streamOpened(1)
    state.streamOpened(2)
    XCTAssertTrue(state.beginClosing())
    XCTAssertEqual(state.streamClosed(2), .none)
    XCTAssertEqual(state.streamClosed(1), .close)
  }

  func testOpenAndCloseStreamWhenClosed() {
    var state = self.makeStateMachine()
    _ = state.closed()
    state.streamOpened(1)
    XCTAssertEqual(state.streamClosed(1), .none)
  }

  func testSendKeepalivePing() {
    var state = self.makeStateMachine(keepaliveWithoutCalls: false)
    // No streams open so ping isn't allowed.
    XCTAssertFalse(state.sendKeepalivePing())

    // Stream open, ping allowed.
    state.streamOpened(1)
    XCTAssertTrue(state.sendKeepalivePing())

    // No stream, no ping.
    XCTAssertEqual(state.streamClosed(1), .startIdleTimer(cancelKeepalive: true))
    XCTAssertFalse(state.sendKeepalivePing())
  }

  func testSendKeepalivePingWhenAllowedWithoutCalls() {
    var state = self.makeStateMachine(keepaliveWithoutCalls: true)
    // Keep alive is allowed when no streams are open, so pings are allowed.
    XCTAssertTrue(state.sendKeepalivePing())

    state.streamOpened(1)
    XCTAssertTrue(state.sendKeepalivePing())

    XCTAssertEqual(state.streamClosed(1), .startIdleTimer(cancelKeepalive: false))
    XCTAssertTrue(state.sendKeepalivePing())
  }

  func testSendKeepalivePingWhenClosing() {
    var state = self.makeStateMachine(keepaliveWithoutCalls: false)
    state.streamOpened(1)
    XCTAssertTrue(state.beginClosing())

    // Stream is opened and state is closing, ping is allowed.
    XCTAssertTrue(state.sendKeepalivePing())
  }

  func testSendKeepalivePingWhenClosed() {
    var state = self.makeStateMachine(keepaliveWithoutCalls: true)
    _ = state.closed()
    XCTAssertFalse(state.sendKeepalivePing())
  }

  func testBeginGracefulShutdownWhenStreamsAreOpen() {
    var state = self.makeStateMachine()
    state.streamOpened(1)
    // Close is false as streams are still open.
    XCTAssertEqual(state.beginGracefulShutdown(promise: nil), .sendGoAway(false))
  }

  func testBeginGracefulShutdownWhenNoStreamsAreOpen() {
    var state = self.makeStateMachine()
    // Close immediately, not streams are open.
    XCTAssertEqual(state.beginGracefulShutdown(promise: nil), .sendGoAway(true))
  }
}
