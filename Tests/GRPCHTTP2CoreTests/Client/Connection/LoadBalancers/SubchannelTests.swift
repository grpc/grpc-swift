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

import GRPCCore
import GRPCHTTP2Core
import NIOCore
import NIOHTTP2
import NIOPosix
import XCTest

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class SubchannelTests: XCTestCase {
  func testMakeStreamOnIdleSubchannel() async throws {
    let subchannel = self.makeSubchannel(
      address: .unixDomainSocket(path: "ignored"),
      connector: .never
    )

    await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
      try await subchannel.makeStream(descriptor: .echoGet, options: .defaults)
    } errorHandler: { error in
      XCTAssertEqual(error.code, .unavailable)
    }

    subchannel.shutDown()
  }

  func testMakeStreamOnShutdownSubchannel() async throws {
    let subchannel = self.makeSubchannel(
      address: .unixDomainSocket(path: "ignored"),
      connector: .never
    )

    subchannel.shutDown()
    await subchannel.run()

    await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
      try await subchannel.makeStream(descriptor: .echoGet, options: .defaults)
    } errorHandler: { error in
      XCTAssertEqual(error.code, .unavailable)
    }
  }

  func testMakeStreamOnReadySubchannel() async throws {
    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()
    let subchannel = self.makeSubchannel(address: address, connector: .posix())

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await server.run { inbound, outbound in
          for try await part in inbound {
            switch part {
            case .metadata:
              try await outbound.write(.metadata([:]))
            case .message(let message):
              try await outbound.write(.message(message))
            }
          }
          try await outbound.write(.status(Status(code: .ok, message: ""), [:]))
        }
      }

      group.addTask {
        await subchannel.run()
      }

      subchannel.connect()

      for await event in subchannel.events {
        switch event {
        case .connectivityStateChanged(.ready):
          let stream = try await subchannel.makeStream(descriptor: .echoGet, options: .defaults)
          try await stream.execute { inbound, outbound in
            try await outbound.write(.metadata([:]))
            try await outbound.write(.message([0, 1, 2]))
            outbound.finish()

            for try await part in inbound {
              switch part {
              case .metadata:
                ()  // Don't validate, contains http/2 specific metadata too.
              case .message(let message):
                XCTAssertEqual(message, [0, 1, 2])
              case .status(let status, _):
                XCTAssertEqual(status.code, .ok)
                XCTAssertEqual(status.message, "")
              }
            }
          }
          subchannel.shutDown()

        default:
          ()
        }
      }

      group.cancelAll()
    }
  }

  func testConnectEventuallySucceeds() async throws {
    let path = "test-connect-eventually-succeeds"
    let subchannel = self.makeSubchannel(
      address: .unixDomainSocket(path: path),
      connector: .posix(),
      backoff: .fixed(at: .milliseconds(10))
    )

    await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { await subchannel.run() }

      var hasServer = false
      var events = [Subchannel.Event]()

      for await event in subchannel.events {
        events.append(event)
        switch event {
        case .connectivityStateChanged(.idle):
          subchannel.connect()

        case .connectivityStateChanged(.transientFailure):
          // Don't start more than one server.
          if hasServer { continue }
          hasServer = true

          group.addTask {
            let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
            _ = try await server.bind(to: .uds(path))
            try await server.run { _, _ in
              XCTFail("Unexpected stream")
            }
          }

        case .connectivityStateChanged(.ready):
          subchannel.shutDown()

        case .connectivityStateChanged(.shutdown):
          group.cancelAll()

        default:
          ()
        }
      }

      // First four events are known:
      XCTAssertEqual(
        Array(events.prefix(4)),
        [
          .connectivityStateChanged(.idle),
          .connectivityStateChanged(.connecting),
          .connectivityStateChanged(.transientFailure),
          .connectivityStateChanged(.connecting),
        ]
      )

      // Because there is backoff timing involved, the subchannel may flip from transient failure
      // to connecting multiple times. Just check that it eventually becomes ready and is then
      // shutdown.
      XCTAssertEqual(
        Array(events.suffix(2)),
        [
          .connectivityStateChanged(.ready),
          .connectivityStateChanged(.shutdown),
        ]
      )
    }
  }

  func testConnectIteratesThroughAddresses() async throws {
    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()
    let subchannel = self.makeSubchannel(
      addresses: [
        .unixDomainSocket(path: "not-listening-1"),
        .unixDomainSocket(path: "not-listening-2"),
        address,
      ],
      connector: .posix()
    )

    await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await server.run { _, _ in
          XCTFail("Unexpected stream")
        }
      }

      group.addTask {
        await subchannel.run()
      }

      for await event in subchannel.events {
        switch event {
        case .connectivityStateChanged(.idle):
          subchannel.connect()
        case .connectivityStateChanged(.ready):
          subchannel.shutDown()
        case .connectivityStateChanged(.shutdown):
          group.cancelAll()
        default:
          ()
        }
      }
    }
  }

  func testConnectIteratesThroughAddressesWithBackoff() async throws {
    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let udsPath = "test-wrap-around-addrs"

    let subchannel = self.makeSubchannel(
      addresses: [
        .unixDomainSocket(path: "not-listening-1"),
        .unixDomainSocket(path: "not-listening-2"),
        .unixDomainSocket(path: udsPath),
      ],
      connector: .posix(),
      backoff: .fixed(at: .zero)  // Skip the backoff period
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        await subchannel.run()
      }

      var isServerRunning = false

      for await event in subchannel.events {
        switch event {
        case .connectivityStateChanged(.idle):
          subchannel.connect()

        case .connectivityStateChanged(.transientFailure):
          // The subchannel enters the transient failure state when all addresses have been tried.
          // Bind the server now so that the next attempts succeeds.
          if isServerRunning { break }
          isServerRunning = true

          let address = try await server.bind(to: .uds(udsPath))
          XCTAssertEqual(address, .unixDomainSocket(path: udsPath))
          group.addTask {
            try await server.run { _, _ in
              XCTFail("Unexpected stream")
            }
          }

        case .connectivityStateChanged(.ready):
          subchannel.shutDown()

        case .connectivityStateChanged(.shutdown):
          group.cancelAll()

        default:
          ()
        }
      }
    }
  }

  func testIdleTimeout() async throws {
    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()
    let subchannel = self.makeSubchannel(
      address: address,
      connector: .posix(maxIdleTime: .milliseconds(1))  // Aggressively idle
    )

    await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        await subchannel.run()
      }

      group.addTask {
        try await server.run { _, _ in
          XCTFail("Unexpected stream")
        }
      }

      var idleCount = 0
      var events = [Subchannel.Event]()
      for await event in subchannel.events {
        events.append(event)
        switch event {
        case .connectivityStateChanged(.idle):
          idleCount += 1
          if idleCount == 1 {
            subchannel.connect()
          } else {
            subchannel.shutDown()
          }

        case .connectivityStateChanged(.shutdown):
          group.cancelAll()

        default:
          ()
        }
      }

      let expected: [Subchannel.Event] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.shutdown),
      ]

      XCTAssertEqual(events, expected)
    }
  }

  func testConnectionDropWhenIdle() async throws {
    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()
    let subchannel = self.makeSubchannel(address: address, connector: .posix())

    await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        await subchannel.run()
      }

      group.addTask {
        try await server.run { _, _ in
          XCTFail("Unexpected RPC")
        }
      }

      var events = [Subchannel.Event]()
      var idleCount = 0

      for await event in subchannel.events {
        events.append(event)

        switch event {
        case .connectivityStateChanged(.idle):
          idleCount += 1
          switch idleCount {
          case 1:
            subchannel.connect()
          case 2:
            subchannel.shutDown()
          default:
            XCTFail("Unexpected idle")
          }

        case .connectivityStateChanged(.ready):
          // Close the connection without a GOAWAY.
          server.clients.first?.close(mode: .all, promise: nil)

        case .connectivityStateChanged(.shutdown):
          group.cancelAll()

        default:
          ()
        }
      }

      let expected: [Subchannel.Event] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.shutdown),
      ]

      XCTAssertEqual(events, expected)
    }
  }

  func testConnectionDropWithOpenStreams() async throws {
    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()
    let subchannel = self.makeSubchannel(address: address, connector: .posix())

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        await subchannel.run()
      }

      group.addTask {
        try await server.run(.echo)
      }

      var events = [Subchannel.Event]()
      var readyCount = 0

      for await event in subchannel.events {
        events.append(event)
        switch event {
        case .connectivityStateChanged(.idle):
          subchannel.connect()

        case .connectivityStateChanged(.ready):
          readyCount += 1
          // When the connection becomes ready the first time, open a stream and forcibly close the
          // channel. This will result in an automatic reconnect. Close the subchannel when that
          // happens.
          if readyCount == 1 {
            let stream = try await subchannel.makeStream(descriptor: .echoGet, options: .defaults)
            try await stream.execute { inbound, outbound in
              try await outbound.write(.metadata([:]))

              // Wait for the metadata to be echo'd back.
              var iterator = inbound.makeAsyncIterator()
              let _ = try await iterator.next()

              // Stream is definitely open. Bork the connection.
              server.clients.first?.close(mode: .all, promise: nil)

              // Wait for the next message which won't arrive, client won't send a message. The
              // stream should fail
              let _ = try await iterator.next()
            }
          } else if readyCount == 2 {
            subchannel.shutDown()
          }

        case .connectivityStateChanged(.shutdown):
          group.cancelAll()

        default:
          ()
        }
      }

      let expected: [Subchannel.Event] = [
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.transientFailure),
        .requiresNameResolution,
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        .connectivityStateChanged(.shutdown),
      ]

      XCTAssertEqual(events, expected)
    }
  }

  func testConnectedReceivesGoAway() async throws {
    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()
    let subchannel = self.makeSubchannel(address: address, connector: .posix())

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await server.run { _, _ in
          XCTFail("Unexpected stream")
        }
      }

      group.addTask {
        await subchannel.run()
      }

      var events = [Subchannel.Event]()

      var idleCount = 0
      for await event in subchannel.events {
        events.append(event)

        switch event {
        case .connectivityStateChanged(.idle):
          idleCount += 1
          if idleCount == 1 {
            subchannel.connect()
          } else if idleCount == 2 {
            subchannel.shutDown()
          }

        case .connectivityStateChanged(.ready):
          // Now the subchannel is ready, send a GOAWAY from the server.
          let channel = try XCTUnwrap(server.clients.first)
          let goAway = HTTP2Frame(
            streamID: .rootStream,
            payload: .goAway(lastStreamID: 0, errorCode: .cancel, opaqueData: nil)
          )
          try await channel.writeAndFlush(goAway)

        case .connectivityStateChanged(.shutdown):
          group.cancelAll()

        default:
          ()
        }
      }

      let expectedEvents: [Subchannel.Event] = [
        // Normal connect flow.
        .connectivityStateChanged(.idle),
        .connectivityStateChanged(.connecting),
        .connectivityStateChanged(.ready),
        // GOAWAY triggers name resolution and idling.
        .goingAway,
        .requiresNameResolution,
        .connectivityStateChanged(.idle),
        // The second idle triggers a close.
        .connectivityStateChanged(.shutdown),
      ]

      XCTAssertEqual(expectedEvents, events)
    }
  }

  func testCancelReadySubchannel() async throws {
    let server = TestServer(eventLoopGroup: .singletonMultiThreadedEventLoopGroup)
    let address = try await server.bind()
    let subchannel = self.makeSubchannel(address: address, connector: .posix())

    await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await server.run { _, _ in
          XCTFail("Unexpected stream")
        }
      }

      group.addTask {
        subchannel.connect()
        await subchannel.run()
      }

      for await event in subchannel.events {
        switch event {
        case .connectivityStateChanged(.ready):
          group.cancelAll()
        default:
          ()
        }
      }
    }
  }

  private func makeSubchannel(
    addresses: [GRPCHTTP2Core.SocketAddress],
    connector: any HTTP2Connector,
    backoff: ConnectionBackoff? = nil
  ) -> Subchannel {
    return Subchannel(
      endpoint: Endpoint(addresses: addresses),
      id: SubchannelID(),
      connector: connector,
      backoff: backoff ?? .defaults,
      defaultCompression: .none,
      enabledCompression: .none
    )
  }

  private func makeSubchannel(
    address: GRPCHTTP2Core.SocketAddress,
    connector: any HTTP2Connector,
    backoff: ConnectionBackoff? = nil
  ) -> Subchannel {
    self.makeSubchannel(addresses: [address], connector: connector, backoff: backoff)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ConnectionBackoff {
  static func fixed(at interval: Duration, jitter: Double = 0.0) -> Self {
    return Self(initial: interval, max: interval, multiplier: 1.0, jitter: jitter)
  }

  static var defaults: Self {
    ConnectionBackoff(initial: .seconds(10), max: .seconds(120), multiplier: 1.6, jitter: 1.2)
  }
}
