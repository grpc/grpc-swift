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

import DequeModule
import GRPCCore
@_spi(Package) @testable import GRPCHTTP2Core
import NIOConcurrencyHelpers
import NIOCore
import NIOHPACK
import NIOHTTP2
import NIOPosix
import XCTest

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class ConnectionTests: XCTestCase {
  func testConnectThenClose() async throws {
    try await ConnectionTest.run(connector: .posix()) { context, event in
      switch event {
      case .connectSucceeded:
        context.connection.close()
      default:
        ()
      }
    } validateEvents: { _, events in
      XCTAssertEqual(events, [.connectSucceeded, .closed(.initiatedLocally)])
    }
  }

  func testConnectThenIdleTimeout() async throws {
    try await ConnectionTest.run(connector: .posix(maxIdleTime: .milliseconds(50))) { _, events in
      XCTAssertEqual(events, [.connectSucceeded, .closed(.idleTimeout)])
    }
  }

  func testConnectThenKeepaliveTimeout() async throws {
    try await ConnectionTest.run(
      connector: .posix(
        keepaliveTime: .milliseconds(50),
        keepaliveTimeout: .milliseconds(10),
        keepaliveWithoutCalls: true,
        dropPingAcks: true
      )
    ) { _, events in
      XCTAssertEqual(events, [.connectSucceeded, .closed(.keepaliveTimeout)])
    }
  }

  func testGoAwayWhenConnected() async throws {
    try await ConnectionTest.run(connector: .posix()) { context, event in
      switch event {
      case .connectSucceeded:
        let goAway = HTTP2Frame(
          streamID: .rootStream,
          payload: .goAway(
            lastStreamID: 0,
            errorCode: .noError,
            opaqueData: ByteBuffer(string: "Hello!")
          )
        )

        let accepted = try context.server.acceptedChannel
        accepted.writeAndFlush(goAway, promise: nil)

      default:
        ()
      }
    } validateEvents: { _, events in
      XCTAssertEqual(events, [.connectSucceeded, .goingAway(.noError, "Hello!"), .closed(.remote)])
    }
  }

  func testConnectFails() async throws {
    let error = RPCError(code: .unimplemented, message: "")
    try await ConnectionTest.run(connector: .throwing(error)) { _, events in
      XCTAssertEqual(events, [.connectFailed(error)])
    }
  }

  func testConnectFailsOnAcceptedThenClosedTCPConnection() async throws {
    try await ConnectionTest.run(connector: .posix(), server: .closeOnAccept) { _, events in
      XCTAssertEqual(events.count, 1)
      let event = try XCTUnwrap(events.first)
      switch event {
      case .connectFailed(let error):
        XCTAssert(error, as: RPCError.self) { rpcError in
          XCTAssertEqual(rpcError.code, .unavailable)
        }
      default:
        XCTFail("Expected '.connectFailed', got '\(event)'")
      }
    }
  }

  func testMakeStreamOnActiveConnection() async throws {
    try await ConnectionTest.run(connector: .posix()) { context, event in
      switch event {
      case .connectSucceeded:
        let stream = try await context.connection.makeStream(
          descriptor: .echoGet,
          options: .defaults
        )
        try await stream.execute { inbound, outbound in
          try await outbound.write(.metadata(["foo": "bar", "bar": "baz"]))
          try await outbound.write(.message([0, 1, 2]))
          outbound.finish()

          var parts = [RPCResponsePart]()
          for try await part in inbound {
            switch part {
            case .metadata(let metadata):
              // Filter out any transport specific metadata
              parts.append(.metadata(Metadata(metadata.suffix(2))))
            case .message, .status:
              parts.append(part)
            }
          }

          let expected: [RPCResponsePart] = [
            .metadata(["foo": "bar", "bar": "baz"]),
            .message([0, 1, 2]),
            .status(Status(code: .ok, message: ""), [:]),
          ]
          XCTAssertEqual(parts, expected)
        }

        context.connection.close()

      default:
        ()
      }
    } validateEvents: { _, events in
      XCTAssertEqual(events, [.connectSucceeded, .closed(.initiatedLocally)])
    }
  }

  func testMakeStreamOnClosedConnection() async throws {
    try await ConnectionTest.run(connector: .posix()) { context, event in
      switch event {
      case .connectSucceeded:
        context.connection.close()
      case .closed:
        await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
          _ = try await context.connection.makeStream(descriptor: .echoGet, options: .defaults)
        } errorHandler: { error in
          XCTAssertEqual(error.code, .unavailable)
        }
      default:
        ()
      }
    } validateEvents: { context, events in
      XCTAssertEqual(events, [.connectSucceeded, .closed(.initiatedLocally)])
    }
  }

  func testMakeStreamOnNotRunningConnection() async throws {
    let connection = Connection(
      address: .ipv4(host: "ignored", port: 0),
      http2Connector: .never,
      defaultCompression: .none,
      enabledCompression: .none
    )

    await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
      _ = try await connection.makeStream(descriptor: .echoGet, options: .defaults)
    } errorHandler: { error in
      XCTAssertEqual(error.code, .unavailable)
    }
  }
}

extension ClientBootstrap {
  func connect<T>(
    to address: GRPCHTTP2Core.SocketAddress,
    _ configure: @Sendable @escaping (Channel) -> EventLoopFuture<T>
  ) async throws -> T {
    if let ipv4 = address.ipv4 {
      return try await self.connect(
        host: ipv4.host,
        port: ipv4.port,
        channelInitializer: configure
      )
    } else if let ipv6 = address.ipv6 {
      return try await self.connect(
        host: ipv6.host,
        port: ipv6.port,
        channelInitializer: configure
      )
    } else if let uds = address.unixDomainSocket {
      return try await self.connect(
        unixDomainSocketPath: uds.path,
        channelInitializer: configure
      )
    } else if let vsock = address.virtualSocket {
      return try await self.connect(
        to: VsockAddress(
          cid: .init(Int(vsock.contextID.rawValue)),
          port: .init(Int(vsock.port.rawValue))
        ),
        channelInitializer: configure
      )
    } else {
      throw RPCError(code: .unimplemented, message: "Unhandled socket address: \(address)")
    }
  }
}

extension Metadata {
  init(_ sequence: some Sequence<Element>) {
    var metadata = Metadata()
    for (key, value) in sequence {
      switch value {
      case .string(let value):
        metadata.addString(value, forKey: key)
      case .binary(let value):
        metadata.addBinary(value, forKey: key)
      }
    }

    self = metadata
  }
}
