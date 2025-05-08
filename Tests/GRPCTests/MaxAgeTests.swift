/*
 * Copyright 2025, gRPC Authors All rights reserved.
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

import EchoImplementation
import EchoModel
import GRPC
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import XCTest

final class MaxAgeTests: XCTestCase {
  private func withEchoClient(
    group: any EventLoopGroup,
    configure: (inout GRPCChannelPool.Configuration) -> Void,
    test: (Echo_EchoNIOClient) throws -> Void
  ) throws {
    let eventLoop = MultiThreadedEventLoopGroup.singleton.next()

    let server = try Server.insecure(group: group)
      .withServiceProviders([EchoProvider()])
      .bind(host: "127.0.0.1", port: 0)
      .wait()

    defer {
      try? server.close().wait()
    }

    let port = server.channel.localAddress!.port!

    let pool = try GRPCChannelPool.with(
      target: .host("127.0.0.1", port: port),
      transportSecurity: .plaintext,
      eventLoopGroup: eventLoop,
      configure
    )

    defer {
      try? pool.close().wait()
    }

    try test(Echo_EchoNIOClient(channel: pool))
  }

  func testMaxAgeIsRespected() throws {
    // Verifies that the max-age config is respected by using the connection pool delegate to
    // start new RPCs when each connection closes (which close by aging out). It'll also record
    // various events that happen as part of the lifecycle of each connection.

    // The pool creates one sub-pool per event loop. Use a single loop to simplify connection
    // counting.
    let eventLoop = MultiThreadedEventLoopGroup.singleton.next()
    let done = eventLoop.makePromise(of: [RPCOnConnectionClosedDelegate.Event].self)
    let iterations = 2
    let delegate = RPCOnConnectionClosedDelegate(iterations: iterations, done: done)
    // This needs to be relatively short so the test doesn't take too long but not so short that
    // the connection is closed before it's actually used.
    let maxConnectionAge: TimeAmount = .milliseconds(50)

    try withEchoClient(group: eventLoop) { config in
      config.maxConnectionAge = maxConnectionAge
      config.delegate = delegate
    } test: { echo in
      // This creates a retain cycle (delegate → echo → channel → delegate), break it when the
      // test is done.
      delegate.setEcho(echo)
      defer { delegate.setEcho(nil) }

      let startTime = NIODeadline.now()

      // Do an RPC to kick things off.
      let rpc = try echo.get(.with { $0.text = "hello" }).response.wait()
      XCTAssertEqual(rpc.text, "Swift echo get: hello")

      // Wait for the delegate to finish driving the RPCs.
      let events = try done.futureResult.wait()
      let endTime = NIODeadline.now()

      // Add an iteration as one is done by the test (as opposed to the delegate). Each iteration
      // has three events: connected, quiescing, closed.
      XCTAssertEqual(events.count, (iterations + 1) * 3)

      // Check each triplet is as expected: connected, quiescing, then closed.
      for startIndex in stride(from: events.startIndex, to: events.endIndex, by: 3) {
        switch (events[startIndex], events[startIndex + 1], events[startIndex + 2]) {
        case (.connectSucceeded(let id1), .connectionQuiescing(let id2), .connectionClosed(let id3)):
          XCTAssertEqual(id1, id2)
          XCTAssertEqual(id2, id3)
        default:
          XCTFail("Invalid event triplet: \(events[startIndex ... startIndex + 2])")
        }
      }

      // Check the duration was in the right ballpark.
      let duration = (endTime - startTime)
      let minDuration = iterations * maxConnectionAge
      XCTAssertGreaterThanOrEqual(duration, minDuration)
      // Allow a few seconds of slack for max duration as some CI systems can be slow.
      let maxDuration = iterations * maxConnectionAge + .seconds(5)
      XCTAssertLessThanOrEqual(duration, maxDuration)
    }
  }

  private final class RPCOnConnectionClosedDelegate: GRPCConnectionPoolDelegate {
    enum Event: Sendable, Hashable {
      case connectSucceeded(GRPCConnectionID)
      case connectionQuiescing(GRPCConnectionID)
      case connectionClosed(GRPCConnectionID)
    }

    private struct State {
      var events: [Event] = []
      var echo: Echo_EchoNIOClient? = nil
      var iterations: Int
    }

    private let state: NIOLockedValueBox<State>
    private let done: EventLoopPromise<[Event]>

    func setEcho(_ echo: Echo_EchoNIOClient?) {
      self.state.withLockedValue { state in
        state.echo = echo
      }
    }

    init(iterations: Int, done: EventLoopPromise<[Event]>) {
      self.state = NIOLockedValueBox(State(iterations: iterations))
      self.done = done
    }

    func connectSucceeded(id: GRPCConnectionID, streamCapacity: Int) {
      self.state.withLockedValue { state in
        state.events.append(.connectSucceeded(id))
      }
    }

    func connectionQuiescing(id: GRPCConnectionID) {
      self.state.withLockedValue { state in
        state.events.append(.connectionQuiescing(id))
      }
    }

    func connectionClosed(id: GRPCConnectionID, error: (any Error)?) {
      enum Action {
        case doNextRPC(Echo_EchoNIOClient)
        case done([Event])
      }

      let action: Action = self.state.withLockedValue { state in
        state.events.append(.connectionClosed(id))

        if state.iterations > 0 {
          state.iterations -= 1
          return .doNextRPC(state.echo!)
        } else {
          return .done(state.events)
        }
      }

      switch action {
      case .doNextRPC(let echo):
        // Start an RPC to trigger a connect. The result doesn't matter:
        _ = echo.get(.with { $0.text = "hello" })
      case .done(let events):
        self.done.succeed(events)
      }
    }

    func connectionAdded(id: GRPCConnectionID) {}
    func connectionRemoved(id: GRPCConnectionID) {}
    func startedConnecting(id: GRPCConnectionID) {}
    func connectFailed(id: GRPCConnectionID, error: any Error) {}
    func connectionUtilizationChanged(id: GRPCConnectionID, streamsUsed: Int, streamCapacity: Int) {
    }
  }

  func testRPCContinuesAfterQuiescing() throws {
    // Check that an in-flight RPC can continue to run after the connection is quiescing as a result
    // of aging out.

    // The pool creates one sub-pool per event loop. Use a single loop to simplify connection
    // counting.
    let eventLoop = MultiThreadedEventLoopGroup.singleton.next()
    let isQuiescing = eventLoop.makePromise(of: Void.self)

    try withEchoClient(group: eventLoop) { config in
      config.maxConnectionAge = .milliseconds(50)
      config.delegate = SucceedOnQuiescing(promise: isQuiescing)
    } test: { echo in
      // Send an initial message.
      let rpc = echo.collect()
      try rpc.sendMessage(.with { $0.text = "1" }).wait()

      // Wait for the connection to quiesce.
      try isQuiescing.futureResult.wait()

      // Send a few more messages then end.
      try rpc.sendMessage(.with { $0.text = "2" }).wait()
      try rpc.sendMessage(.with { $0.text = "3" }).wait()
      try rpc.sendEnd().wait()

      let response = try rpc.response.wait()
      XCTAssertEqual(response.text, "Swift echo collect: 1 2 3")
    }
  }

  final class SucceedOnQuiescing: GRPCConnectionPoolDelegate {
    private let quiescingPromise: EventLoopPromise<Void>

    init(promise: EventLoopPromise<Void>) {
      self.quiescingPromise = promise
    }

    func connectionQuiescing(id: GRPCConnectionID) {
      self.quiescingPromise.succeed()
    }

    func connectionAdded(id: GRPCConnectionID) {}
    func connectionRemoved(id: GRPCConnectionID) {}
    func startedConnecting(id: GRPCConnectionID) {}
    func connectFailed(id: GRPCConnectionID, error: any Error) {}
    func connectSucceeded(id: GRPCConnectionID, streamCapacity: Int) {}
    func connectionUtilizationChanged(id: GRPCConnectionID, streamsUsed: Int, streamCapacity: Int) {
    }
    func connectionClosed(id: GRPCConnectionID, error: (any Error)?) {}
  }

}
