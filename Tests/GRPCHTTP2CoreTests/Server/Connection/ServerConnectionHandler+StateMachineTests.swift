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
import NIOHTTP2
import XCTest

@testable import GRPCHTTP2Core

final class ServerConnectionHandlerStateMachineTests: XCTestCase {
  private func makeStateMachine(
    allowKeepAliveWithoutCalls: Bool = false,
    minPingReceiveIntervalWithoutCalls: TimeAmount = .minutes(5),
    goAwayPingData: HTTP2PingData = HTTP2PingData(withInteger: 42)
  ) -> ServerConnectionHandler.StateMachine {
    return .init(
      allowKeepAliveWithoutCalls: allowKeepAliveWithoutCalls,
      minPingReceiveIntervalWithoutCalls: minPingReceiveIntervalWithoutCalls,
      goAwayPingData: goAwayPingData
    )
  }

  func testCloseAllStreamsWhenActive() {
    var state = self.makeStateMachine()
    state.streamOpened(1)
    XCTAssertEqual(state.streamClosed(1), .startIdleTimer)
  }

  func testCloseSomeStreamsWhenActive() {
    var state = self.makeStateMachine()
    state.streamOpened(1)
    state.streamOpened(2)
    XCTAssertEqual(state.streamClosed(2), .none)
  }

  func testOpenAndCloseStreamWhenClosed() {
    var state = self.makeStateMachine()
    state.markClosed()
    state.streamOpened(1)
    XCTAssertEqual(state.streamClosed(1), .none)
  }

  func testGracefulShutdownWhenNoOpenStreams() {
    let pingData = HTTP2PingData(withInteger: 42)
    var state = self.makeStateMachine(goAwayPingData: pingData)
    XCTAssertEqual(state.startGracefulShutdown(), .sendGoAwayAndPing(pingData))
  }

  func testGracefulShutdownWhenClosing() {
    let pingData = HTTP2PingData(withInteger: 42)
    var state = self.makeStateMachine(goAwayPingData: pingData)
    XCTAssertEqual(state.startGracefulShutdown(), .sendGoAwayAndPing(pingData))
    XCTAssertEqual(state.startGracefulShutdown(), .none)
  }

  func testGracefulShutdownWhenClosed() {
    let pingData = HTTP2PingData(withInteger: 42)
    var state = self.makeStateMachine(goAwayPingData: pingData)
    state.markClosed()
    XCTAssertEqual(state.startGracefulShutdown(), .none)
  }

  func testReceiveAckForGoAwayPingWhenStreamsOpenedBeforeShutdownOnly() {
    let pingData = HTTP2PingData(withInteger: 42)
    var state = self.makeStateMachine(goAwayPingData: pingData)
    state.streamOpened(1)
    XCTAssertEqual(state.startGracefulShutdown(), .sendGoAwayAndPing(pingData))
    XCTAssertEqual(
      state.receivedPingAck(data: pingData),
      .sendGoAway(lastStreamID: 1, close: false)
    )
  }

  func testReceiveAckForGoAwayPingWhenStreamsOpenedBeforeAck() {
    let pingData = HTTP2PingData(withInteger: 42)
    var state = self.makeStateMachine(goAwayPingData: pingData)
    XCTAssertEqual(state.startGracefulShutdown(), .sendGoAwayAndPing(pingData))
    state.streamOpened(1)
    XCTAssertEqual(
      state.receivedPingAck(data: pingData),
      .sendGoAway(lastStreamID: 1, close: false)
    )
  }

  func testReceiveAckForGoAwayPingWhenNoOpenStreams() {
    let pingData = HTTP2PingData(withInteger: 42)
    var state = self.makeStateMachine(goAwayPingData: pingData)
    XCTAssertEqual(state.startGracefulShutdown(), .sendGoAwayAndPing(pingData))
    XCTAssertEqual(
      state.receivedPingAck(data: pingData),
      .sendGoAway(lastStreamID: .rootStream, close: true)
    )
  }

  func testReceiveAckNotForGoAwayPing() {
    let pingData = HTTP2PingData(withInteger: 42)
    var state = self.makeStateMachine(goAwayPingData: pingData)
    XCTAssertEqual(state.startGracefulShutdown(), .sendGoAwayAndPing(pingData))

    let otherPingData = HTTP2PingData(withInteger: 0)
    XCTAssertEqual(state.receivedPingAck(data: otherPingData), .none)
  }

  func testReceivePingAckWhenActive() {
    var state = self.makeStateMachine()
    XCTAssertEqual(state.receivedPingAck(data: HTTP2PingData()), .none)
  }

  func testReceivePingAckWhenClosed() {
    var state = self.makeStateMachine()
    state.markClosed()
    XCTAssertEqual(state.receivedPingAck(data: HTTP2PingData()), .none)
  }

  func testGracefulShutdownFlow() {
    var state = self.makeStateMachine()
    // Open a few streams.
    state.streamOpened(1)
    state.streamOpened(2)

    switch state.startGracefulShutdown() {
    case .sendGoAwayAndPing(let pingData):
      // Open another stream and then receive the ping ack.
      state.streamOpened(3)
      XCTAssertEqual(
        state.receivedPingAck(data: pingData),
        .sendGoAway(lastStreamID: 3, close: false)
      )
    case .none:
      XCTFail("Expected '.sendGoAwayAndPing'")
    }

    // Both GOAWAY frames have been sent. Start closing streams.
    XCTAssertEqual(state.streamClosed(1), .none)
    XCTAssertEqual(state.streamClosed(2), .none)
    XCTAssertEqual(state.streamClosed(3), .close)
  }

  func testGracefulShutdownWhenNoOpenStreamsBeforeSecondGoAway() {
    var state = self.makeStateMachine()
    // Open a stream.
    state.streamOpened(1)

    switch state.startGracefulShutdown() {
    case .sendGoAwayAndPing(let pingData):
      // Close the stream. This shouldn't lead to a close.
      XCTAssertEqual(state.streamClosed(1), .none)
      // Only on receiving the ack do we send a GOAWAY and close.
      XCTAssertEqual(
        state.receivedPingAck(data: pingData),
        .sendGoAway(lastStreamID: 1, close: true)
      )
    case .none:
      XCTFail("Expected '.sendGoAwayAndPing'")
    }
  }

  func testPingStrikeUsingMinReceiveInterval(
    state: inout ServerConnectionHandler.StateMachine,
    interval: TimeAmount,
    expectedID id: HTTP2StreamID
  ) {
    var time = NIODeadline.now()
    let data = HTTP2PingData()

    // The first ping is never a strike.
    XCTAssertEqual(state.receivedPing(atTime: time, data: data), .sendAck)

    // Advance time by just less than the interval and get two strikes.
    time = time + interval - .nanoseconds(1)
    XCTAssertEqual(state.receivedPing(atTime: time, data: data), .sendAck)
    XCTAssertEqual(state.receivedPing(atTime: time, data: data), .sendAck)

    // Advance time so that we're at one interval since the last valid ping. This isn't a
    // strike (but doesn't reset strikes) and updates the last valid ping time.
    time = time + .nanoseconds(1)
    XCTAssertEqual(state.receivedPing(atTime: time, data: data), .sendAck)

    // Now get a third and final strike.
    XCTAssertEqual(state.receivedPing(atTime: time, data: data), .enhanceYourCalmThenClose(id))
  }

  func testPingStrikesWhenKeepAliveIsNotPermittedWithoutCalls() {
    let initialState = self.makeStateMachine(
      allowKeepAliveWithoutCalls: false,
      minPingReceiveIntervalWithoutCalls: .minutes(5)
    )

    var state = initialState
    state.streamOpened(1)
    self.testPingStrikeUsingMinReceiveInterval(state: &state, interval: .minutes(5), expectedID: 1)

    state = initialState
    self.testPingStrikeUsingMinReceiveInterval(state: &state, interval: .hours(2), expectedID: 0)
  }

  func testPingStrikesWhenKeepAliveIsPermittedWithoutCalls() {
    var state = self.makeStateMachine(
      allowKeepAliveWithoutCalls: true,
      minPingReceiveIntervalWithoutCalls: .minutes(5)
    )

    self.testPingStrikeUsingMinReceiveInterval(state: &state, interval: .minutes(5), expectedID: 0)
  }

  func testResetPingStrikeState() {
    var state = self.makeStateMachine(
      allowKeepAliveWithoutCalls: true,
      minPingReceiveIntervalWithoutCalls: .minutes(5)
    )

    var time = NIODeadline.now()
    let data = HTTP2PingData()

    // The first ping is never a strike.
    XCTAssertEqual(state.receivedPing(atTime: time, data: data), .sendAck)

    // Advance time by less than the interval and get two strikes.
    time = time + .minutes(1)
    XCTAssertEqual(state.receivedPing(atTime: time, data: data), .sendAck)
    XCTAssertEqual(state.receivedPing(atTime: time, data: data), .sendAck)

    // Reset the ping strike state and test ping strikes as normal.
    state.resetKeepAliveState()
    self.testPingStrikeUsingMinReceiveInterval(state: &state, interval: .minutes(5), expectedID: 0)
  }
}
