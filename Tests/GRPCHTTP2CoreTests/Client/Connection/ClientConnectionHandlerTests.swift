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

final class ClientConnectionHandlerTests: XCTestCase {
  func testMaxIdleTime() throws {
    let connection = try Connection(maxIdleTime: .minutes(5))
    try connection.activate()

    // Idle with no streams open we should:
    // - read out a closing event,
    // - write a GOAWAY frame,
    // - close.
    connection.loop.advanceTime(by: .minutes(5))

    XCTAssertEqual(try connection.readEvent(), .closing(.idle))

    let frame = try XCTUnwrap(try connection.readFrame())
    XCTAssertEqual(frame.streamID, .rootStream)
    XCTAssertGoAway(frame.payload) { lastStreamID, error, data in
      XCTAssertEqual(lastStreamID, .rootStream)
      XCTAssertEqual(error, .noError)
      XCTAssertEqual(data, ByteBuffer(string: "idle"))
    }

    try connection.waitUntilClosed()
  }

  func testMaxIdleTimeWhenOpenStreams() throws {
    let connection = try Connection(maxIdleTime: .minutes(5))
    try connection.activate()

    // Open a stream, the idle timer should be cancelled.
    connection.streamOpened(1)

    // Advance by the idle time, nothing should happen.
    connection.loop.advanceTime(by: .minutes(5))
    XCTAssertNil(try connection.readEvent())
    XCTAssertNil(try connection.readFrame())

    // Close the stream, the idle timer should begin again.
    connection.streamClosed(1)
    connection.loop.advanceTime(by: .minutes(5))
    let frame = try XCTUnwrap(try connection.readFrame())
    XCTAssertGoAway(frame.payload) { lastStreamID, error, data in
      XCTAssertEqual(lastStreamID, .rootStream)
      XCTAssertEqual(error, .noError)
      XCTAssertEqual(data, ByteBuffer(string: "idle"))
    }

    try connection.waitUntilClosed()
  }

  func testKeepAliveWithOpenStreams() throws {
    let connection = try Connection(keepAliveTime: .minutes(1), keepAliveTimeout: .seconds(10))
    try connection.activate()

    // Open a stream so keep-alive starts.
    connection.streamOpened(1)

    for _ in 0 ..< 10 {
      // Advance time, a PING should be sent, ACK it.
      connection.loop.advanceTime(by: .minutes(1))
      let frame1 = try XCTUnwrap(connection.readFrame())
      XCTAssertEqual(frame1.streamID, .rootStream)
      try XCTAssertPing(frame1.payload) { data, ack in
        XCTAssertFalse(ack)
        try connection.ping(data: data, ack: true)
      }

      XCTAssertNil(try connection.readFrame())
    }

    // Close the stream, keep-alive pings should stop.
    connection.streamClosed(1)
    connection.loop.advanceTime(by: .minutes(1))
    XCTAssertNil(try connection.readFrame())
  }

  func testKeepAliveWithNoOpenStreams() throws {
    let connection = try Connection(keepAliveTime: .minutes(1), allowKeepAliveWithoutCalls: true)
    try connection.activate()

    for _ in 0 ..< 10 {
      // Advance time, a PING should be sent, ACK it.
      connection.loop.advanceTime(by: .minutes(1))
      let frame1 = try XCTUnwrap(connection.readFrame())
      XCTAssertEqual(frame1.streamID, .rootStream)
      try XCTAssertPing(frame1.payload) { data, ack in
        XCTAssertFalse(ack)
        try connection.ping(data: data, ack: true)
      }

      XCTAssertNil(try connection.readFrame())
    }
  }

  func testKeepAliveWithOpenStreamsTimingOut() throws {
    let connection = try Connection(keepAliveTime: .minutes(1), keepAliveTimeout: .seconds(10))
    try connection.activate()

    // Open a stream so keep-alive starts.
    connection.streamOpened(1)

    // Advance time, a PING should be sent, don't ACK it.
    connection.loop.advanceTime(by: .minutes(1))
    let frame1 = try XCTUnwrap(connection.readFrame())
    XCTAssertEqual(frame1.streamID, .rootStream)
    XCTAssertPing(frame1.payload) { _, ack in
      XCTAssertFalse(ack)
    }

    // Advance time by the keep alive timeout. We should:
    // - read a connection event
    // - read out a GOAWAY frame
    // - be closed
    connection.loop.advanceTime(by: .seconds(10))

    XCTAssertEqual(try connection.readEvent(), .closing(.keepAliveExpired))

    let frame2 = try XCTUnwrap(connection.readFrame())
    XCTAssertEqual(frame2.streamID, .rootStream)
    XCTAssertGoAway(frame2.payload) { lastStreamID, error, data in
      XCTAssertEqual(lastStreamID, .rootStream)
      XCTAssertEqual(error, .noError)
      XCTAssertEqual(data, ByteBuffer(string: "keepalive_expired"))
    }

    // Doesn't wait for streams to close: the connection is bad.
    try connection.waitUntilClosed()
  }

  func testPingsAreIgnored() throws {
    let connection = try Connection()
    try connection.activate()

    // PING frames without ack set should be ignored, we rely on the HTTP/2 handler replying to them.
    try connection.ping(data: HTTP2PingData(), ack: false)
    XCTAssertNil(try connection.readFrame())
  }

  func testReceiveGoAway() throws {
    let connection = try Connection()
    try connection.activate()

    try connection.goAway(
      lastStreamID: 0,
      errorCode: .enhanceYourCalm,
      opaqueData: ByteBuffer(string: "too_many_pings")
    )

    // Should read out an event and close (because there are no open streams).
    XCTAssertEqual(
      try connection.readEvent(),
      .closing(.goAway(.enhanceYourCalm, "too_many_pings"))
    )
    try connection.waitUntilClosed()
  }

  func testReceiveGoAwayWithOpenStreams() throws {
    let connection = try Connection()
    try connection.activate()

    connection.streamOpened(1)
    connection.streamOpened(2)
    connection.streamOpened(3)

    try connection.goAway(lastStreamID: .maxID, errorCode: .noError)

    // Should read out an event.
    XCTAssertEqual(try connection.readEvent(), .closing(.goAway(.noError, "")))

    // Close streams so the connection can close.
    connection.streamClosed(1)
    connection.streamClosed(2)
    connection.streamClosed(3)
    try connection.waitUntilClosed()
  }

  func testOutboundGracefulClose() throws {
    let connection = try Connection()
    try connection.activate()

    connection.streamOpened(1)
    let closed = connection.closeGracefully()
    XCTAssertEqual(try connection.readEvent(), .closing(.initiatedLocally))
    connection.streamClosed(1)
    try closed.wait()
  }
}

extension ClientConnectionHandlerTests {
  struct Connection {
    let channel: EmbeddedChannel
    var loop: EmbeddedEventLoop {
      self.channel.embeddedEventLoop
    }

    init(
      maxIdleTime: TimeAmount? = nil,
      keepAliveTime: TimeAmount? = nil,
      keepAliveTimeout: TimeAmount? = nil,
      allowKeepAliveWithoutCalls: Bool = false
    ) throws {
      let loop = EmbeddedEventLoop()
      let handler = ClientConnectionHandler(
        eventLoop: loop,
        maxIdleTime: maxIdleTime,
        keepAliveTime: keepAliveTime,
        keepAliveTimeout: keepAliveTimeout,
        keepAliveWithoutCalls: allowKeepAliveWithoutCalls
      )

      self.channel = EmbeddedChannel(handler: handler, loop: loop)
    }

    func activate() throws {
      try self.channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
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

    func goAway(
      lastStreamID: HTTP2StreamID,
      errorCode: HTTP2ErrorCode,
      opaqueData: ByteBuffer? = nil
    ) throws {
      let frame = HTTP2Frame(
        streamID: .rootStream,
        payload: .goAway(lastStreamID: lastStreamID, errorCode: errorCode, opaqueData: opaqueData)
      )

      try self.channel.writeInbound(frame)
    }

    func ping(data: HTTP2PingData, ack: Bool) throws {
      let frame = HTTP2Frame(streamID: .rootStream, payload: .ping(data, ack: ack))
      try self.channel.writeInbound(frame)
    }

    func readFrame() throws -> HTTP2Frame? {
      return try self.channel.readOutbound(as: HTTP2Frame.self)
    }

    func readEvent() throws -> ClientConnectionEvent? {
      return try self.channel.readInbound(as: ClientConnectionEvent.self)
    }

    func waitUntilClosed() throws {
      self.channel.embeddedEventLoop.run()
      try self.channel.closeFuture.wait()
    }

    func closeGracefully() -> EventLoopFuture<Void> {
      let promise = self.channel.embeddedEventLoop.makePromise(of: Void.self)
      let event = ClientConnectionHandler.OutboundEvent.closeGracefully
      self.channel.pipeline.triggerUserOutboundEvent(event, promise: promise)
      return promise.futureResult
    }
  }
}
