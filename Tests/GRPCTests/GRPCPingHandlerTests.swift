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
@testable import GRPC
import NIOCore
import NIOEmbedded
import NIOHTTP2
import XCTest

class GRPCPingHandlerTests: GRPCTestCase {
  var pingHandler: PingHandler!

  func testClosingStreamWithoutPermitCalls() {
    // Do not allow pings without calls
    self.setupPingHandler(interval: .seconds(1), timeout: .seconds(1))

    // New stream created
    var response: PingHandler.Action = self.pingHandler.streamCreated()
    XCTAssertEqual(response, .schedulePing(delay: .seconds(1), timeout: .seconds(1)))

    // Stream closed
    response = self.pingHandler.streamClosed()
    XCTAssertEqual(response, .none)
  }

  func testClosingStreamWithPermitCalls() {
    // Allow pings without calls (since `minimumReceivedPingIntervalWithoutData` and `maximumPingStrikes` are not set, ping strikes should not have any effect)
    self.setupPingHandler(interval: .seconds(1), timeout: .seconds(1), permitWithoutCalls: true)

    // New stream created
    var response: PingHandler.Action = self.pingHandler.streamCreated()
    XCTAssertEqual(response, .schedulePing(delay: .seconds(1), timeout: .seconds(1)))

    // Stream closed
    response = self.pingHandler.streamClosed()
    XCTAssertEqual(response, .none)
  }

  func testIntervalWithCallInFlight() {
    // Do not allow pings without calls
    self.setupPingHandler(interval: .seconds(1), timeout: .seconds(1))

    // New stream created
    var response: PingHandler.Action = self.pingHandler.streamCreated()
    XCTAssertEqual(response, .schedulePing(delay: .seconds(1), timeout: .seconds(1)))

    // Move time to 1 second in the future
    self.pingHandler._testingOnlyNow = .now() + .seconds(1)

    // Send ping, which is valid
    response = self.pingHandler.pingFired()
    XCTAssertEqual(
      response,
      .reply(HTTP2Frame.FramePayload.ping(HTTP2PingData(withInteger: 1), ack: false))
    )

    // Received valid pong, scheduled timeout should be cancelled
    response = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: true)
    XCTAssertEqual(response, .cancelScheduledTimeout)

    // Stream closed
    response = self.pingHandler.streamClosed()
    XCTAssertEqual(response, .none)
  }

  func testIntervalWithoutCallsInFlight() {
    // Do not allow pings without calls
    self.setupPingHandler(interval: .seconds(1), timeout: .seconds(1))

    // Send ping, which is invalid
    let response: PingHandler.Action = self.pingHandler.pingFired()
    XCTAssertEqual(response, .none)
  }

  func testIntervalWithCallNoLongerInFlight() {
    // Do not allow pings without calls
    self.setupPingHandler(interval: .seconds(1), timeout: .seconds(1))

    // New stream created
    var response: PingHandler.Action = self.pingHandler.streamCreated()
    XCTAssertEqual(response, .schedulePing(delay: .seconds(1), timeout: .seconds(1)))

    // Stream closed
    response = self.pingHandler.streamClosed()
    XCTAssertEqual(response, .none)

    // Move time to 1 second in the future
    self.pingHandler._testingOnlyNow = .now() + .seconds(1)

    // Send ping, which is invalid
    response = self.pingHandler.pingFired()
    XCTAssertEqual(response, .none)
  }

  func testIntervalWithoutCallsInFlightButPermitted() {
    // Allow pings without calls (since `minimumReceivedPingIntervalWithoutData` and `maximumPingStrikes` are not set, ping strikes should not have any effect)
    self.setupPingHandler(interval: .seconds(1), timeout: .seconds(1), permitWithoutCalls: true)

    // Send ping, which is valid
    var response: PingHandler.Action = self.pingHandler.pingFired()
    XCTAssertEqual(
      response,
      .reply(HTTP2Frame.FramePayload.ping(HTTP2PingData(withInteger: 1), ack: false))
    )

    // Received valid pong, scheduled timeout should be cancelled
    response = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: true)
    XCTAssertEqual(response, .cancelScheduledTimeout)
  }

  func testIntervalWithCallNoLongerInFlightButPermitted() {
    // Allow pings without calls (since `minimumReceivedPingIntervalWithoutData` and `maximumPingStrikes` are not set, ping strikes should not have any effect)
    self.setupPingHandler(interval: .seconds(1), timeout: .seconds(1), permitWithoutCalls: true)

    // New stream created
    var response: PingHandler.Action = self.pingHandler.streamCreated()
    XCTAssertEqual(response, .schedulePing(delay: .seconds(1), timeout: .seconds(1)))

    // Stream closed
    response = self.pingHandler.streamClosed()
    XCTAssertEqual(response, .none)

    // Move time to 1 second in the future
    self.pingHandler._testingOnlyNow = .now() + .seconds(1)

    // Send ping, which is valid
    response = self.pingHandler.pingFired()
    XCTAssertEqual(
      response,
      .reply(HTTP2Frame.FramePayload.ping(HTTP2PingData(withInteger: 1), ack: false))
    )

    // Received valid pong, scheduled timeout should be cancelled
    response = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: true)
    XCTAssertEqual(response, .cancelScheduledTimeout)
  }

  func testIntervalTooEarlyWithCallInFlight() {
    // Do not allow pings without calls
    self.setupPingHandler(interval: .seconds(2), timeout: .seconds(1))

    // New stream created
    var response: PingHandler.Action = self.pingHandler.streamCreated()
    XCTAssertEqual(response, .schedulePing(delay: .seconds(2), timeout: .seconds(1)))

    // Send first ping
    response = self.pingHandler.pingFired()
    XCTAssertEqual(
      response,
      .reply(HTTP2Frame.FramePayload.ping(HTTP2PingData(withInteger: 1), ack: false))
    )

    // Move time to 1 second in the future
    self.pingHandler._testingOnlyNow = .now() + .seconds(1)

    // Send another ping, which is valid since client do not check ping strikes
    response = self.pingHandler.pingFired()
    XCTAssertEqual(
      response,
      .reply(HTTP2Frame.FramePayload.ping(HTTP2PingData(withInteger: 1), ack: false))
    )

    // Stream closed
    response = self.pingHandler.streamClosed()
    XCTAssertEqual(response, .none)
  }

  func testIntervalTooEarlyWithoutCallsInFlight() {
    // Allow pings without calls with a maximum pings of 2
    self.setupPingHandler(
      interval: .seconds(2),
      timeout: .seconds(1),
      permitWithoutCalls: true,
      maximumPingsWithoutData: 2,
      minimumSentPingIntervalWithoutData: .seconds(5)
    )

    // Send first ping
    var response: PingHandler.Action = self.pingHandler.pingFired()
    XCTAssertEqual(
      response,
      .reply(HTTP2Frame.FramePayload.ping(HTTP2PingData(withInteger: 1), ack: false))
    )

    // Move time to 1 second in the future
    self.pingHandler._testingOnlyNow = .now() + .seconds(1)

    // Send another ping, but since `now` is less than the ping interval, response should be no action
    response = self.pingHandler.pingFired()
    XCTAssertEqual(response, .none)

    // Move time to 5 seconds in the future
    self.pingHandler._testingOnlyNow = .now() + .seconds(5)

    // Send another ping, which is valid since we waited `minimumSentPingIntervalWithoutData`
    response = self.pingHandler.pingFired()
    XCTAssertEqual(
      response,
      .reply(HTTP2Frame.FramePayload.ping(HTTP2PingData(withInteger: 1), ack: false))
    )

    // Move time to 10 seconds in the future
    self.pingHandler._testingOnlyNow = .now() + .seconds(10)

    // Send another ping, which is valid since we waited `minimumSentPingIntervalWithoutData`
    response = self.pingHandler.pingFired()
    XCTAssertEqual(
      response,
      .reply(HTTP2Frame.FramePayload.ping(HTTP2PingData(withInteger: 1), ack: false))
    )

    // Send another ping, but we've exceeded `maximumPingsWithoutData` so response should be no action
    response = self.pingHandler.pingFired()
    XCTAssertEqual(response, .none)

    // New stream created
    response = self.pingHandler.streamCreated()
    XCTAssertEqual(response, .schedulePing(delay: .seconds(2), timeout: .seconds(1)))

    // Send another ping, now that there is call, ping is valid
    response = self.pingHandler.pingFired()
    XCTAssertEqual(
      response,
      .reply(HTTP2Frame.FramePayload.ping(HTTP2PingData(withInteger: 1), ack: false))
    )

    // Stream closed
    response = self.pingHandler.streamClosed()
    XCTAssertEqual(response, .none)
  }

  func testPingStrikesOnClientShouldHaveNoEffect() {
    // Allow pings without calls (since `minimumReceivedPingIntervalWithoutData` and `maximumPingStrikes` are not set, ping strikes should not have any effect)
    self.setupPingHandler(interval: .seconds(2), timeout: .seconds(1), permitWithoutCalls: true)

    // Received first ping, response should be a pong
    var response: PingHandler.Action = self.pingHandler.read(
      pingData: HTTP2PingData(withInteger: 1),
      ack: false
    )
    XCTAssertEqual(response, .ack)

    // Received another ping, response should be a pong (ping strikes not in effect)
    response = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: false)
    XCTAssertEqual(response, .ack)

    // Received another ping, response should be a pong (ping strikes not in effect)
    response = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: false)
    XCTAssertEqual(response, .ack)
  }

  func testPingWithoutDataResultsInPongForClient() {
    // Don't allow _sending_ pings when no calls are active (receiving pings should be tolerated).
    self.setupPingHandler(permitWithoutCalls: false)

    let action = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: false)
    XCTAssertEqual(action, .ack)
  }

  func testPingWithoutDataResultsInPongForServer() {
    // Don't allow _sending_ pings when no calls are active (receiving pings should be tolerated).
    // Set 'minimumReceivedPingIntervalWithoutData' and 'maximumPingStrikes' so that we enable
    // support for ping strikes.
    self.setupPingHandler(
      permitWithoutCalls: false,
      minimumReceivedPingIntervalWithoutData: .seconds(5),
      maximumPingStrikes: 1
    )

    let action = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: false)
    XCTAssertEqual(action, .ack)
  }

  func testPingStrikesOnServer() {
    // Set a maximum ping strikes of 1 without a minimum of 1 second between pings
    self.setupPingHandler(
      interval: .seconds(2),
      timeout: .seconds(1),
      permitWithoutCalls: true,
      minimumReceivedPingIntervalWithoutData: .seconds(1),
      maximumPingStrikes: 1
    )

    // Received first ping, response should be a pong
    var response: PingHandler.Action = self.pingHandler.read(
      pingData: HTTP2PingData(withInteger: 1),
      ack: false
    )
    XCTAssertEqual(response, .ack)

    // Received another ping, which is invalid (ping strike), response should be no action
    response = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: false)
    XCTAssertEqual(response, .none)

    // Move time to 2 seconds in the future
    self.pingHandler._testingOnlyNow = .now() + .seconds(2)

    // Received another ping, which is valid now, response should be a pong
    response = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: false)
    XCTAssertEqual(response, .ack)

    // Received another ping, which is invalid (ping strike), response should be no action
    response = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: false)
    XCTAssertEqual(response, .none)

    // Received another ping, which is invalid (ping strike), since number of ping strikes is over the limit, response should be go away
    response = self.pingHandler.read(pingData: HTTP2PingData(withInteger: 1), ack: false)
    XCTAssertEqual(
      response,
      .reply(HTTP2Frame.FramePayload.goAway(
        lastStreamID: .rootStream,
        errorCode: .enhanceYourCalm,
        opaqueData: nil
      ))
    )
  }

  func testPongWithGoAwayPingData() {
    self.setupPingHandler()
    let response = self.pingHandler.read(pingData: self.pingHandler.pingDataGoAway, ack: true)
    XCTAssertEqual(response, .ratchetDownLastSeenStreamID)
  }

  private func setupPingHandler(
    pingCode: UInt64 = 1,
    interval: TimeAmount = .seconds(15),
    timeout: TimeAmount = .seconds(5),
    permitWithoutCalls: Bool = false,
    maximumPingsWithoutData: UInt = 2,
    minimumSentPingIntervalWithoutData: TimeAmount = .seconds(5),
    minimumReceivedPingIntervalWithoutData: TimeAmount? = nil,
    maximumPingStrikes: UInt? = nil
  ) {
    self.pingHandler = PingHandler(
      pingCode: pingCode,
      interval: interval,
      timeout: timeout,
      permitWithoutCalls: permitWithoutCalls,
      maximumPingsWithoutData: maximumPingsWithoutData,
      minimumSentPingIntervalWithoutData: minimumSentPingIntervalWithoutData,
      minimumReceivedPingIntervalWithoutData: minimumReceivedPingIntervalWithoutData,
      maximumPingStrikes: maximumPingStrikes
    )
  }
}

extension PingHandler.Action: Equatable {
  public static func == (lhs: PingHandler.Action, rhs: PingHandler.Action) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
      return true
    case (.ack, .ack):
      return true
    case (let .schedulePing(lhsDelay, lhsTimeout), let .schedulePing(rhsDelay, rhsTimeout)):
      return lhsDelay == rhsDelay && lhsTimeout == rhsTimeout
    case (.cancelScheduledTimeout, .cancelScheduledTimeout):
      return true
    case (.ratchetDownLastSeenStreamID, .ratchetDownLastSeenStreamID):
      return true
    case let (.reply(lhsPayload), .reply(rhsPayload)):
      switch (lhsPayload, rhsPayload) {
      case (let .ping(lhsData, ack: lhsAck), let .ping(rhsData, ack: rhsAck)):
        return lhsData == rhsData && lhsAck == rhsAck
      case (let .goAway(_, lhsErrorCode, _), let .goAway(_, rhsErrorCode, _)):
        return lhsErrorCode == rhsErrorCode
      default:
        return false
      }
    default:
      return false
    }
  }
}

extension GRPCPingHandlerTests {
  func testSingleAckIsEmittedOnPing() throws {
    let client = EmbeddedChannel()
    let _ = try client.configureHTTP2Pipeline(mode: .client) { _ in
      fatalError("Unexpected inbound stream")
    }.wait()

    let server = EmbeddedChannel()
    let serverMux = try server.configureHTTP2Pipeline(mode: .server) { _ in
      fatalError("Unexpected inbound stream")
    }.wait()

    let idleHandler = GRPCIdleHandler(
      idleTimeout: .minutes(5),
      keepalive: .init(),
      logger: self.serverLogger
    )
    try server.pipeline.syncOperations.addHandler(idleHandler, position: .before(serverMux))
    try server.connect(to: .init(unixDomainSocketPath: "/ignored")).wait()
    try client.connect(to: .init(unixDomainSocketPath: "/ignored")).wait()

    func interact(client: EmbeddedChannel, server: EmbeddedChannel) throws {
      var didRead = true
      while didRead {
        didRead = false

        if let data = try client.readOutbound(as: ByteBuffer.self) {
          didRead = true
          try server.writeInbound(data)
        }

        if let data = try server.readOutbound(as: ByteBuffer.self) {
          didRead = true
          try client.writeInbound(data)
        }
      }
    }

    try interact(client: client, server: server)

    // Settings.
    let f1 = try XCTUnwrap(client.readInbound(as: HTTP2Frame.self))
    f1.payload.assertSettings(ack: false)

    // Settings ack.
    let f2 = try XCTUnwrap(client.readInbound(as: HTTP2Frame.self))
    f2.payload.assertSettings(ack: true)

    // Send a ping.
    let ping = HTTP2Frame(streamID: .rootStream, payload: .ping(.init(withInteger: 42), ack: false))
    try client.writeOutbound(ping)
    try interact(client: client, server: server)

    // Ping ack.
    let f3 = try XCTUnwrap(client.readInbound(as: HTTP2Frame.self))
    f3.payload.assertPing(ack: true)

    XCTAssertNil(try client.readInbound(as: HTTP2Frame.self))
  }
}

extension HTTP2Frame.FramePayload {
  func assertSettings(ack: Bool, file: StaticString = #file, line: UInt = #line) {
    switch self {
    case let .settings(settings):
      switch settings {
      case .ack:
        XCTAssertTrue(ack, file: file, line: line)
      case .settings:
        XCTAssertFalse(ack, file: file, line: line)
      }
    default:
      XCTFail("Expected .settings got \(self)", file: file, line: line)
    }
  }

  func assertPing(ack: Bool, file: StaticString = #file, line: UInt = #line) {
    switch self {
    case let .ping(_, ack: pingAck):
      XCTAssertEqual(pingAck, ack, file: file, line: line)
    default:
      XCTFail("Expected .ping got \(self)", file: file, line: line)
    }
  }
}
