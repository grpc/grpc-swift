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
import NIOHTTP2
import XCTest

@testable import GRPCHTTP2Core

final class ServerConnectionManagementHandlerTests: XCTestCase {
  func testIdleTimeoutOnNewConnection() throws {
    let connection = try Connection(maxIdleTime: .minutes(1))
    try connection.activate()
    // Hit the max idle time.
    connection.advanceTime(by: .minutes(1))

    // Follow the graceful shutdown flow.
    try self.testGracefulShutdown(connection: connection, lastStreamID: 0)

    // Closed because no streams were open.
    try connection.waitUntilClosed()
  }

  func testIdleTimerIsCancelledWhenStreamIsOpened() throws {
    let connection = try Connection(maxIdleTime: .minutes(1))
    try connection.activate()

    // Open a stream to cancel the idle timer and run through the max idle time.
    connection.streamOpened(1)
    connection.advanceTime(by: .minutes(1))

    // No GOAWAY frame means the timer was cancelled.
    XCTAssertNil(try connection.readFrame())
  }

  func testIdleTimerStartsWhenAllStreamsAreClosed() throws {
    let connection = try Connection(maxIdleTime: .minutes(1))
    try connection.activate()

    // Open a stream to cancel the idle timer and run through the max idle time.
    connection.streamOpened(1)
    connection.advanceTime(by: .minutes(1))
    XCTAssertNil(try connection.readFrame())

    // Close the stream to start the timer again.
    connection.streamClosed(1)
    connection.advanceTime(by: .minutes(1))

    // Follow the graceful shutdown flow.
    try self.testGracefulShutdown(connection: connection, lastStreamID: 1)

    // Closed because no streams were open.
    try connection.waitUntilClosed()
  }

  func testMaxAge() throws {
    let connection = try Connection(maxAge: .minutes(1))
    try connection.activate()

    // Open some streams.
    connection.streamOpened(1)
    connection.streamOpened(3)

    // Run to the max age and follow the graceful shutdown flow.
    connection.advanceTime(by: .minutes(1))
    try self.testGracefulShutdown(connection: connection, lastStreamID: 3)

    // Close the streams.
    connection.streamClosed(1)
    connection.streamClosed(3)

    // Connection will be closed now.
    try connection.waitUntilClosed()
  }

  func testGracefulShutdownRatchetsDownStreamID() throws {
    // This test uses the idle timeout to trigger graceful shutdown. The mechanism is the same
    // regardless of how it's triggered.
    let connection = try Connection(maxIdleTime: .minutes(1))
    try connection.activate()

    // Trigger the shutdown, but open a stream during shutdown.
    connection.advanceTime(by: .minutes(1))
    try self.testGracefulShutdown(
      connection: connection,
      lastStreamID: 1,
      streamToOpenBeforePingAck: 1
    )

    // Close the stream to trigger closing the connection.
    connection.streamClosed(1)
    try connection.waitUntilClosed()
  }

  func testGracefulShutdownGracePeriod() throws {
    // This test uses the idle timeout to trigger graceful shutdown. The mechanism is the same
    // regardless of how it's triggered.
    let connection = try Connection(
      maxIdleTime: .minutes(1),
      maxGraceTime: .seconds(5)
    )
    try connection.activate()

    // Trigger the shutdown, but open a stream during shutdown.
    connection.advanceTime(by: .minutes(1))
    try self.testGracefulShutdown(
      connection: connection,
      lastStreamID: 1,
      streamToOpenBeforePingAck: 1
    )

    // Wait out the grace period without closing the stream.
    connection.advanceTime(by: .seconds(5))
    try connection.waitUntilClosed()
  }

  func testKeepaliveOnNewConnection() throws {
    let connection = try Connection(
      keepaliveTime: .minutes(5),
      keepaliveTimeout: .seconds(5)
    )
    try connection.activate()

    // Wait for the keep alive timer to fire which should cause the server to send a keep
    // alive PING.
    connection.advanceTime(by: .minutes(5))
    let frame1 = try XCTUnwrap(connection.readFrame())
    XCTAssertEqual(frame1.streamID, .rootStream)
    try XCTAssertPing(frame1.payload) { data, ack in
      XCTAssertFalse(ack)
      // Data is opaque, send it back.
      try connection.ping(data: data, ack: true)
    }

    // Run past the timeout, nothing should happen.
    connection.advanceTime(by: .seconds(5))
    XCTAssertNil(try connection.readFrame())
  }

  func testKeepaliveStartsAfterReadLoop() throws {
    let connection = try Connection(
      keepaliveTime: .minutes(5),
      keepaliveTimeout: .seconds(5)
    )
    try connection.activate()

    // Write a frame into the channel _without_ calling channel read complete. This will cancel
    // the keep alive timer.
    let settings = HTTP2Frame(streamID: .rootStream, payload: .settings(.settings([])))
    connection.channel.pipeline.fireChannelRead(NIOAny(settings))

    // Run out the keep alive timer, it shouldn't fire.
    connection.advanceTime(by: .minutes(5))
    XCTAssertNil(try connection.readFrame())

    // Fire channel read complete to start the keep alive timer again.
    connection.channel.pipeline.fireChannelReadComplete()

    // Now expire the keep alive timer again, we should read out a PING frame.
    connection.advanceTime(by: .minutes(5))
    let frame1 = try XCTUnwrap(connection.readFrame())
    XCTAssertEqual(frame1.streamID, .rootStream)
    XCTAssertPing(frame1.payload) { data, ack in
      XCTAssertFalse(ack)
    }
  }

  func testKeepaliveOnNewConnectionWithoutResponse() throws {
    let connection = try Connection(
      keepaliveTime: .minutes(5),
      keepaliveTimeout: .seconds(5)
    )
    try connection.activate()

    // Wait for the keep alive timer to fire which should cause the server to send a keep
    // alive PING.
    connection.advanceTime(by: .minutes(5))
    let frame1 = try XCTUnwrap(connection.readFrame())
    XCTAssertEqual(frame1.streamID, .rootStream)
    XCTAssertPing(frame1.payload) { data, ack in
      XCTAssertFalse(ack)
    }

    // We didn't ack the PING, the connection should shutdown after the timeout.
    connection.advanceTime(by: .seconds(5))
    try self.testGracefulShutdown(connection: connection, lastStreamID: 0)

    // Connection is closed now.
    try connection.waitUntilClosed()
  }

  func testClientKeepalivePolicing() throws {
    let connection = try Connection(
      allowKeepaliveWithoutCalls: true,
      minPingIntervalWithoutCalls: .minutes(1)
    )
    try connection.activate()

    // The first ping is valid, the second and third are strikes.
    for _ in 1 ... 3 {
      try connection.ping(data: HTTP2PingData(), ack: false)
      let frame = try XCTUnwrap(connection.readFrame())
      XCTAssertEqual(frame.streamID, .rootStream)
      XCTAssertPing(frame.payload) { data, ack in
        XCTAssertEqual(data, HTTP2PingData())
        XCTAssertTrue(ack)
      }
    }

    // The fourth ping is the third strike and triggers a GOAWAY.
    try connection.ping(data: HTTP2PingData(), ack: false)
    let frame = try XCTUnwrap(connection.readFrame())
    XCTAssertEqual(frame.streamID, .rootStream)
    XCTAssertGoAway(frame.payload) { streamID, error, data in
      XCTAssertEqual(streamID, .rootStream)
      XCTAssertEqual(error, .enhanceYourCalm)
      XCTAssertEqual(data, ByteBuffer(string: "too_many_pings"))
    }

    // The server should close the connection.
    try connection.waitUntilClosed()
  }

  func testClientKeepaliveWithPermissibleIntervals() throws {
    let connection = try Connection(
      allowKeepaliveWithoutCalls: true,
      minPingIntervalWithoutCalls: .minutes(1),
      manualClock: true
    )
    try connection.activate()

    for _ in 1 ... 100 {
      try connection.ping(data: HTTP2PingData(), ack: false)
      let frame = try XCTUnwrap(connection.readFrame())
      XCTAssertEqual(frame.streamID, .rootStream)
      XCTAssertPing(frame.payload) { data, ack in
        XCTAssertEqual(data, HTTP2PingData())
        XCTAssertTrue(ack)
      }

      // Advance by the ping interval.
      connection.advanceTime(by: .minutes(1))
    }
  }

  func testClientKeepaliveResetState() throws {
    let connection = try Connection(
      allowKeepaliveWithoutCalls: true,
      minPingIntervalWithoutCalls: .minutes(1)
    )
    try connection.activate()

    func sendThreeKeepalivePings() throws {
      // The first ping is valid, the second and third are strikes.
      for _ in 1 ... 3 {
        try connection.ping(data: HTTP2PingData(), ack: false)
        let frame = try XCTUnwrap(connection.readFrame())
        XCTAssertEqual(frame.streamID, .rootStream)
        XCTAssertPing(frame.payload) { data, ack in
          XCTAssertEqual(data, HTTP2PingData())
          XCTAssertTrue(ack)
        }
      }
    }

    try sendThreeKeepalivePings()

    // "send" a HEADERS frame and flush to reset keep alive state.
    connection.syncView.wroteHeadersFrame()
    connection.syncView.connectionWillFlush()

    // As above, the first ping is valid, the next two are strikes.
    try sendThreeKeepalivePings()

    // The next ping is the third strike and triggers a GOAWAY.
    try connection.ping(data: HTTP2PingData(), ack: false)
    let frame = try XCTUnwrap(connection.readFrame())
    XCTAssertEqual(frame.streamID, .rootStream)
    XCTAssertGoAway(frame.payload) { streamID, error, data in
      XCTAssertEqual(streamID, .rootStream)
      XCTAssertEqual(error, .enhanceYourCalm)
      XCTAssertEqual(data, ByteBuffer(string: "too_many_pings"))
    }

    // The server should close the connection.
    try connection.waitUntilClosed()
  }
}

extension ServerConnectionManagementHandlerTests {
  private func testGracefulShutdown(
    connection: Connection,
    lastStreamID: HTTP2StreamID,
    streamToOpenBeforePingAck: HTTP2StreamID? = nil
  ) throws {
    let frame1 = try XCTUnwrap(connection.readFrame())
    XCTAssertEqual(frame1.streamID, .rootStream)
    XCTAssertGoAway(frame1.payload) { streamID, errorCode, _ in
      XCTAssertEqual(streamID, .maxID)
      XCTAssertEqual(errorCode, .noError)
    }

    // Followed by a PING
    let frame2 = try XCTUnwrap(connection.readFrame())
    XCTAssertEqual(frame2.streamID, .rootStream)
    try XCTAssertPing(frame2.payload) { data, ack in
      XCTAssertFalse(ack)

      if let id = streamToOpenBeforePingAck {
        connection.streamOpened(id)
      }

      // Send the PING ACK.
      try connection.ping(data: data, ack: true)
    }

    // PING ACK triggers another GOAWAY.
    let frame3 = try XCTUnwrap(connection.readFrame())
    XCTAssertEqual(frame3.streamID, .rootStream)
    XCTAssertGoAway(frame3.payload) { streamID, errorCode, _ in
      XCTAssertEqual(streamID, lastStreamID)
      XCTAssertEqual(errorCode, .noError)
    }
  }
}

extension ServerConnectionManagementHandlerTests {
  struct Connection {
    let channel: EmbeddedChannel
    let syncView: ServerConnectionManagementHandler.SyncView

    var loop: EmbeddedEventLoop {
      self.channel.embeddedEventLoop
    }

    private let clock: ServerConnectionManagementHandler.Clock

    init(
      maxIdleTime: TimeAmount? = nil,
      maxAge: TimeAmount? = nil,
      maxGraceTime: TimeAmount? = nil,
      keepaliveTime: TimeAmount? = nil,
      keepaliveTimeout: TimeAmount? = nil,
      allowKeepaliveWithoutCalls: Bool = false,
      minPingIntervalWithoutCalls: TimeAmount = .minutes(5),
      manualClock: Bool = false
    ) throws {
      if manualClock {
        self.clock = .manual(ServerConnectionManagementHandler.Clock.Manual())
      } else {
        self.clock = .nio
      }

      let loop = EmbeddedEventLoop()
      let handler = ServerConnectionManagementHandler(
        eventLoop: loop,
        maxIdleTime: maxIdleTime,
        maxAge: maxAge,
        maxGraceTime: maxGraceTime,
        keepaliveTime: keepaliveTime,
        keepaliveTimeout: keepaliveTimeout,
        allowKeepaliveWithoutCalls: allowKeepaliveWithoutCalls,
        minPingIntervalWithoutCalls: minPingIntervalWithoutCalls,
        clock: self.clock
      )

      self.syncView = handler.syncView
      self.channel = EmbeddedChannel(handler: handler, loop: loop)
    }

    func activate() throws {
      try self.channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
    }

    func advanceTime(by delta: TimeAmount) {
      switch self.clock {
      case .nio:
        ()
      case .manual(let clock):
        clock.advance(by: delta)
      }

      self.loop.advanceTime(by: delta)
    }

    func streamOpened(_ id: HTTP2StreamID) {
      let event = NIOHTTP2StreamCreatedEvent(
        streamID: id,
        localInitialWindowSize: nil,
        remoteInitialWindowSize: nil
      )
      self.channel.pipeline.fireUserInboundEventTriggered(event)
    }

    func streamClosed(_ id: HTTP2StreamID) {
      let event = StreamClosedEvent(streamID: id, reason: nil)
      self.channel.pipeline.fireUserInboundEventTriggered(event)
    }

    func ping(data: HTTP2PingData, ack: Bool) throws {
      let frame = HTTP2Frame(streamID: .rootStream, payload: .ping(data, ack: ack))
      try self.channel.writeInbound(frame)
    }

    func readFrame() throws -> HTTP2Frame? {
      return try self.channel.readOutbound(as: HTTP2Frame.self)
    }

    func waitUntilClosed() throws {
      self.channel.embeddedEventLoop.run()
      try self.channel.closeFuture.wait()
    }
  }
}
