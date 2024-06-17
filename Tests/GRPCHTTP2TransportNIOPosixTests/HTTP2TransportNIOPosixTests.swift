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
import GRPCHTTP2TransportNIOPosix
import XCTest

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class HTTP2TransportNIOPosixTests: XCTestCase {
  func testGetListeningAddress_IPv4() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(
      address: .ipv4(host: "0.0.0.0", port: 0)
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        XCTAssertNotNil(address.ipv4)
        transport.stopListening()
      }
    }
  }

  func testGetListeningAddress_IPv6() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(address: .ipv6(host: "::1", port: 0))

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        XCTAssertNotNil(address.ipv6)
        transport.stopListening()
      }
    }
  }

  func testGetListeningAddress_UnixDomainSocket() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(
      address: .unixDomainSocket(path: "/tmp/test")
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        XCTAssertEqual(
          address.unixDomainSocket,
          GRPCHTTP2Core.SocketAddress.UnixDomainSocket(path: "/tmp/test")
        )
        transport.stopListening()
      }
    }
  }

  func testGetListeningAddress_InvalidAddress() async {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(
      address: .unixDomainSocket(path: "/this/is/an/invalid/path")
    )
    let expectation = expectation(description: "Getting address threw")

    try? await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }
      }

      group.addTask {
        do {
          _ = try await transport.listeningAddress
        } catch let error as RuntimeError {
          expectation.fulfill()
          XCTAssertEqual(error.code, .serverIsStopped)
          XCTAssertEqual(
            error.message,
            """
            There is no listening address bound for this server: there may have \
            been an error which caused the transport to close, or it may have shut down.
            """
          )
        }
      }
    }

    await fulfillment(of: [expectation])
  }

  func testGetListeningAddress_StoppedListening() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(
      address: .ipv4(host: "0.0.0.0", port: 0)
    )
    let expectation = expectation(description: "Getting address threw")

    try? await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }

        do {
          _ = try await transport.listeningAddress
        } catch let error as RuntimeError {
          expectation.fulfill()
          XCTAssertEqual(error.code, .serverIsStopped)
          XCTAssertEqual(
            error.message,
            """
            There is no listening address bound for this server: there may have \
            been an error which caused the transport to close, or it may have shut down.
            """
          )
        }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        XCTAssertNotNil(address.ipv4)
        transport.stopListening()
      }
    }

    await fulfillment(of: [expectation])
  }
}
