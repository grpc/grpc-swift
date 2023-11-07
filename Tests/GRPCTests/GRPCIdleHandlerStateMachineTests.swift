/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIOHTTP2
import XCTest

@testable import GRPC

class GRPCIdleHandlerStateMachineTests: GRPCTestCase {
  private func makeClientStateMachine() -> GRPCIdleHandlerStateMachine {
    return GRPCIdleHandlerStateMachine(role: .client, logger: self.clientLogger)
  }

  private func makeServerStateMachine() -> GRPCIdleHandlerStateMachine {
    return GRPCIdleHandlerStateMachine(role: .server, logger: self.serverLogger)
  }

  private func makeNoOpScheduled() -> Scheduled<Void> {
    let loop = EmbeddedEventLoop()
    return loop.scheduleTask(deadline: .distantFuture) { return () }
  }

  func testInactiveBeforeSettings() {
    var stateMachine = self.makeClientStateMachine()
    let op1 = stateMachine.channelInactive()
    op1.assertConnectionManager(.inactive)
  }

  func testInactiveAfterSettings() {
    var stateMachine = self.makeClientStateMachine()
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)

    let readyStateMachine = stateMachine

    // Inactive with a stream open.
    let op2 = stateMachine.streamCreated(withID: 1)
    op2.assertDoNothing()
    let op3 = stateMachine.channelInactive()
    op3.assertConnectionManager(.inactive)

    // Inactive with no open streams.
    stateMachine = readyStateMachine
    let op4 = stateMachine.channelInactive()
    op4.assertConnectionManager(.idle)
  }

  func testInactiveWhenWaitingToIdle() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Schedule the timeout.
    let op2 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op2.assertDoNothing()

    // Become inactive unexpectedly.
    let op3 = stateMachine.channelInactive()
    op3.assertConnectionManager(.idle)
  }

  func testInactiveWhenQuiescing() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)

    // Try a few combinations: initiator of shutdown, and whether streams are open or not when
    // shutdown is initiated.
    let readyStateMachine = stateMachine

    // (1) Peer initiates shutdown, no streams are open.
    do {
      let op2 = stateMachine.receiveGoAway()
      op2.assertGoAway(streamID: .rootStream)
      op2.assertShouldClose()

      // We become idle.
      let op3 = stateMachine.channelInactive()
      op3.assertConnectionManager(.idle)
    }

    // (2) We initiate shutdown, no streams are open.
    stateMachine = readyStateMachine
    do {
      let op2 = stateMachine.initiateGracefulShutdown()
      op2.assertGoAway(streamID: .rootStream)
      op2.assertShouldClose()

      // We become idle.
      let op3 = stateMachine.channelInactive()
      op3.assertConnectionManager(.idle)
    }

    stateMachine = readyStateMachine
    _ = stateMachine.streamCreated(withID: 1)
    let streamOpenStateMachine = stateMachine

    // (3) Peer initiates shutdown, streams are open.
    do {
      let op2 = stateMachine.receiveGoAway()
      op2.assertNoGoAway()
      op2.assertShouldNotClose()

      // We become inactive.
      let op3 = stateMachine.channelInactive()
      op3.assertConnectionManager(.inactive)
    }

    // (4) We initiate shutdown, streams are open.
    stateMachine = streamOpenStateMachine
    do {
      let op2 = stateMachine.initiateGracefulShutdown()
      op2.assertShouldNotClose()

      // We become inactive.
      let op3 = stateMachine.channelInactive()
      op3.assertConnectionManager(.inactive)
    }
  }

  func testReceiveSettings() {
    var stateMachine = self.makeClientStateMachine()

    // No open streams.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Open streams.
    stateMachine = self.makeClientStateMachine()
    let op2 = stateMachine.streamCreated(withID: 1)
    op2.assertDoNothing()
    let op3 = stateMachine.receiveSettings([])
    // No idle timeout to cancel.
    op3.assertConnectionManager(.ready)
    op3.assertNoIdleTimeoutTask()
  }

  func testReceiveSettingsWhenWaitingToIdle() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Receive more settings.
    let op2 = stateMachine.receiveSettings([])
    op2.assertDoNothing()

    // Schedule the timeout.
    let op3 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op3.assertDoNothing()

    // More settings.
    let op4 = stateMachine.receiveSettings([])
    op4.assertDoNothing()
  }

  func testReceiveGoAwayWhenWaitingToIdle() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Schedule the timeout.
    let op2 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op2.assertDoNothing()

    // Receive a GOAWAY frame.
    let op3 = stateMachine.receiveGoAway()
    op3.assertGoAway(streamID: .rootStream)
    op3.assertShouldClose()
    op3.assertCancelIdleTimeout()

    // Close; we were going to go idle anyway.
    let op4 = stateMachine.channelInactive()
    op4.assertConnectionManager(.idle)
  }

  func testInitiateGracefulShutdownWithNoOpenStreams() {
    var stateMachine = self.makeClientStateMachine()

    // No open streams: so GOAWAY and close.
    let op1 = stateMachine.initiateGracefulShutdown()
    op1.assertGoAway(streamID: .rootStream)
    op1.assertShouldClose()

    // Closed.
    let op2 = stateMachine.channelInactive()
    op2.assertConnectionManager(.inactive)
  }

  func testInitiateGracefulShutdownWithOpenStreams() {
    var stateMachine = self.makeClientStateMachine()

    // Open a stream.
    let op1 = stateMachine.streamCreated(withID: 1)
    op1.assertDoNothing()

    // Initiate shutdown.
    let op2 = stateMachine.initiateGracefulShutdown()
    op2.assertShouldNotClose()

    // Receive a GOAWAY; no change.
    let op3 = stateMachine.receiveGoAway()
    op3.assertDoNothing()

    // Close the remaining open stream, connection should close as a result.
    let op4 = stateMachine.streamClosed(withID: 1)
    op4.assertShouldClose()

    // Connection closed.
    let op5 = stateMachine.channelInactive()
    op5.assertConnectionManager(.inactive)
  }

  func testInitiateGracefulShutdownWhenWaitingToIdle() {
    var stateMachine = self.makeClientStateMachine()

    // Become 'ready'
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Schedule the task.
    let op2 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op2.assertDoNothing()

    // Initiate shutdown: cancel the timeout, send a GOAWAY and close.
    let op3 = stateMachine.initiateGracefulShutdown()
    op3.assertCancelIdleTimeout()
    op3.assertGoAway(streamID: .rootStream)
    op3.assertShouldClose()

    // Closed: become inactive.
    let op4 = stateMachine.channelInactive()
    op4.assertConnectionManager(.inactive)
  }

  func testInitiateGracefulShutdownWhenQuiescing() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Open a few streams.
    for streamID in stride(from: HTTP2StreamID(1), to: HTTP2StreamID(6), by: 2) {
      let op = stateMachine.streamCreated(withID: streamID)
      op.assertDoNothing()
    }

    // Receive a GOAWAY.
    let op2 = stateMachine.receiveGoAway()
    op2.assertNoGoAway()

    // Initiate shutdown from our side: we've already sent GOAWAY and have a stream open, we don't
    // need to do anything.
    let op3 = stateMachine.initiateGracefulShutdown()
    op3.assertDoNothing()

    // Close the first couple of streams; should be a no-op.
    for streamID in [HTTP2StreamID(1), HTTP2StreamID(3)] {
      let op = stateMachine.streamClosed(withID: streamID)
      op.assertDoNothing()
    }
    // Close the final stream.
    let op4 = stateMachine.streamClosed(withID: 5)
    op4.assertShouldClose()

    // Initiate shutdown again: we're closing so this should be a no-op.
    let op5 = stateMachine.initiateGracefulShutdown()
    op5.assertDoNothing()

    // Closed.
    let op6 = stateMachine.channelInactive()
    op6.assertConnectionManager(.inactive)
  }

  func testScheduleIdleTaskWhenStreamsAreOpen() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Open a stream before scheduling the task.
    let op2 = stateMachine.streamCreated(withID: 1)
    op2.assertDoNothing()

    // Schedule an idle timeout task: there are open streams so this should be cancelled.
    let op3 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op3.assertCancelIdleTimeout()
  }

  func testScheduleIdleTaskWhenQuiescing() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Save the state machine so we can test a few branches.
    let readyStateMachine = stateMachine

    // (1) Scheduled when quiescing.
    let op2 = stateMachine.streamCreated(withID: 1)
    op2.assertDoNothing()
    // Start shutting down.
    _ = stateMachine.initiateGracefulShutdown()
    // Schedule an idle timeout task: we're quiescing, so cancel the task.
    let op4 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op4.assertCancelIdleTimeout()

    // (2) Scheduled when closing.
    stateMachine = readyStateMachine
    let op5 = stateMachine.initiateGracefulShutdown()
    op5.assertGoAway(streamID: .rootStream)
    op5.assertShouldClose()
    // Schedule an idle timeout task: we're already closing, so cancel the task.
    let op6 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op6.assertCancelIdleTimeout()
  }

  func testIdleTimeoutTaskFiresWhenIdle() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Schedule the task.
    let op2 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op2.assertDoNothing()

    // Fire the task.
    let op3 = stateMachine.idleTimeoutTaskFired()
    op3.assertGoAway(streamID: .rootStream)
    op3.assertShouldClose()

    // Close.
    let op4 = stateMachine.channelInactive()
    op4.assertConnectionManager(.idle)
  }

  func testIdleTimeoutTaskFiresWhenClosed() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Schedule the task.
    let op2 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op2.assertDoNothing()

    // Close.
    let op3 = stateMachine.channelInactive()
    op3.assertCancelIdleTimeout()

    // Fire the idle timeout task.
    let op4 = stateMachine.idleTimeoutTaskFired()
    op4.assertDoNothing()
  }

  func testShutdownNow() {
    var stateMachine = self.makeClientStateMachine()

    let op1 = stateMachine.shutdownNow()
    op1.assertGoAway(streamID: .rootStream)
    op1.assertShouldClose()

    let op2 = stateMachine.channelInactive()
    op2.assertConnectionManager(.inactive)
  }

  func testShutdownNowWhenWaitingToIdle() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Schedule the task.
    let op2 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op2.assertDoNothing()

    let op3 = stateMachine.shutdownNow()
    op3.assertGoAway(streamID: .rootStream)
    op3.assertShouldClose()

    let op4 = stateMachine.channelInactive()
    op4.assertConnectionManager(.inactive)
  }

  func testShutdownNowWhenQuiescing() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Open a stream.
    let op2 = stateMachine.streamCreated(withID: 1)
    op2.assertDoNothing()

    // Initiate shutdown.
    let op3 = stateMachine.initiateGracefulShutdown()
    op3.assertNoGoAway()

    // Shutdown now.
    let op4 = stateMachine.shutdownNow()
    op4.assertShouldClose()
  }

  func testNormalFlow() {
    var stateMachine = self.makeClientStateMachine()

    // Become ready.
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Schedule the task.
    let op2 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op2.assertDoNothing()

    // Create a stream to cancel the task.
    let op3 = stateMachine.streamCreated(withID: 1)
    op3.assertCancelIdleTimeout()

    // Close the stream.
    let op4 = stateMachine.streamClosed(withID: 1)
    op4.assertScheduleIdleTimeout()

    // Receive a GOAWAY frame.
    let op5 = stateMachine.receiveGoAway()
    // We're the client, there are no server initiated streams, so GOAWAY with root stream.
    op5.assertGoAway(streamID: 0)
    // No open streams, so we can close now.
    op5.assertShouldClose()

    // Closed.
    let op6 = stateMachine.channelInactive()
    // The peer initiated shutdown by sending GOAWAY, we'll idle.
    op6.assertConnectionManager(.idle)
  }

  func testClientSendsGoAwayAndOpensStream() {
    var stateMachine = self.makeServerStateMachine()

    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)
    op1.assertScheduleIdleTimeout()

    // Schedule the idle timeout.
    let op2 = stateMachine.scheduledIdleTimeoutTask(self.makeNoOpScheduled())
    op2.assertDoNothing()

    // Create a stream to cancel the task.
    let op3 = stateMachine.streamCreated(withID: 1)
    op3.assertCancelIdleTimeout()

    // Receive a GOAWAY frame from the client.
    let op4 = stateMachine.receiveGoAway()
    op4.assertGoAway(streamID: .maxID)
    op4.assertShouldPingAfterGoAway()

    // Create another stream. This is fine, the client hasn't ack'd the ping yet.
    let op5 = stateMachine.streamCreated(withID: 7)
    op5.assertDoNothing()

    // Receiving the ping is handled by a different state machine which will tell us to ratchet
    // down the go away stream ID.
    let op6 = stateMachine.ratchetDownGoAwayStreamID()
    op6.assertGoAway(streamID: 7)
    op6.assertShouldNotPingAfterGoAway()

    let op7 = stateMachine.streamClosed(withID: 7)
    op7.assertDoNothing()

    let op8 = stateMachine.streamClosed(withID: 1)
    op8.assertShouldClose()
  }

  func testRatchetDownStreamIDWhenNotQuiescing() {
    var stateMachine = self.makeServerStateMachine()
    _ = stateMachine.receiveSettings([])

    // from the 'operating' state.
    stateMachine.ratchetDownGoAwayStreamID().assertDoNothing()

    // move to the 'waiting to idle' state.
    let promise = EmbeddedEventLoop().makePromise(of: Void.self)
    let task = Scheduled(promise: promise, cancellationTask: {})
    stateMachine.scheduledIdleTimeoutTask(task).assertDoNothing()
    promise.succeed(())
    stateMachine.ratchetDownGoAwayStreamID().assertDoNothing()

    // move to 'closing'
    _ = stateMachine.idleTimeoutTaskFired()
    stateMachine.ratchetDownGoAwayStreamID().assertDoNothing()

    // move to 'closed'
    _ = stateMachine.channelInactive()
    stateMachine.ratchetDownGoAwayStreamID().assertDoNothing()
  }

  func testStreamIDWhenQuiescing() {
    var stateMachine = self.makeClientStateMachine()
    let op1 = stateMachine.receiveSettings([])
    op1.assertConnectionManager(.ready)

    // Open a stream so we enter quiescing when receiving the GOAWAY.
    let op2 = stateMachine.streamCreated(withID: 1)
    op2.assertDoNothing()

    let op3 = stateMachine.receiveGoAway()
    op3.assertConnectionManager(.quiescing)

    // Create a new stream. This can happen if the GOAWAY races with opening the stream; HTTP2 will
    // open and then close the stream with an error.
    let op4 = stateMachine.streamCreated(withID: 3)
    op4.assertDoNothing()

    // Close the newly opened stream.
    let op5 = stateMachine.streamClosed(withID: 3)
    op5.assertDoNothing()

    // Close the original stream.
    let op6 = stateMachine.streamClosed(withID: 1)
    // Now we can send a GOAWAY with stream ID zero (we're the client and the server didn't open
    // any streams).
    XCTAssertEqual(op6.sendGoAwayWithLastPeerInitiatedStreamID, 0)
  }
}

extension GRPCIdleHandlerStateMachine.Operations {
  func assertDoNothing() {
    XCTAssertNil(self.connectionManagerEvent)
    XCTAssertNil(self.idleTask)
    XCTAssertNil(self.sendGoAwayWithLastPeerInitiatedStreamID)
    XCTAssertFalse(self.shouldCloseChannel)
    XCTAssertFalse(self.shouldPingAfterGoAway)
  }

  func assertGoAway(streamID: HTTP2StreamID) {
    XCTAssertEqual(self.sendGoAwayWithLastPeerInitiatedStreamID, streamID)
  }

  func assertNoGoAway() {
    XCTAssertNil(self.sendGoAwayWithLastPeerInitiatedStreamID)
  }

  func assertScheduleIdleTimeout() {
    switch self.idleTask {
    case .some(.schedule):
      ()
    case .some(.cancel), .none:
      XCTFail("Expected 'schedule' but was '\(String(describing: self.idleTask))'")
    }
  }

  func assertCancelIdleTimeout() {
    switch self.idleTask {
    case .some(.cancel):
      ()
    case .some(.schedule), .none:
      XCTFail("Expected 'cancel' but was '\(String(describing: self.idleTask))'")
    }
  }

  func assertNoIdleTimeoutTask() {
    XCTAssertNil(self.idleTask)
  }

  func assertConnectionManager(_ event: GRPCIdleHandlerStateMachine.ConnectionManagerEvent) {
    XCTAssertEqual(self.connectionManagerEvent, event)
  }

  func assertNoConnectionManagerEvent() {
    XCTAssertNil(self.connectionManagerEvent)
  }

  func assertShouldClose() {
    XCTAssertTrue(self.shouldCloseChannel)
  }

  func assertShouldNotClose() {
    XCTAssertFalse(self.shouldCloseChannel)
  }

  func assertShouldPingAfterGoAway() {
    XCTAssert(self.shouldPingAfterGoAway)
  }

  func assertShouldNotPingAfterGoAway() {
    XCTAssertFalse(self.shouldPingAfterGoAway)
  }
}
