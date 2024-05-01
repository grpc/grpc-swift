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
@_spi(Package) @testable import GRPCHTTP2Core
import NIOCore
import NIOHTTP2
import NIOPosix
import XCTest

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
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

    subchannel.close()
  }

  func testMakeStreamOnShutdownSubchannel() async throws {
    let subchannel = self.makeSubchannel(
      address: .unixDomainSocket(path: "ignored"),
      connector: .never
    )

    subchannel.close()
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
          subchannel.close()

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
      backoff: .fixed(at: .milliseconds(100))
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
          subchannel.close()

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
          subchannel.close()
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
          subchannel.close()

        case .connectivityStateChanged(.shutdown):
          group.cancelAll()

        default:
          ()
        }
      }
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

      for await event in subchannel.events {
        events.append(event)

        switch event {
        case .connectivityStateChanged(.idle):
          subchannel.connect()

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
        // GOAWAY triggers name resolution too.
        .goingAway,
        .requiresNameResolution,
        // Finally, shutdown.
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

extension ConnectionBackoff {
  static func fixed(at interval: Duration, jitter: Double = 0.0) -> Self {
    return Self(initial: interval, max: interval, multiplier: 1.0, jitter: jitter)
  }

  static var defaults: Self {
    ConnectionBackoff(initial: .seconds(10), max: .seconds(120), multiplier: 1.6, jitter: 1.2)
  }
}
