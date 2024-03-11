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
import GRPCInProcessTransport
import XCTest

@testable import InteroperabilityTests

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class InProcessInteroperabilityTests: XCTestCase {
  func runInProcessTransport(
    interopTestCase: InteroperabilityTestCase
  ) async throws {
    do {
      let inProcess = InProcessTransport.makePair()
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          let server = GRPCServer(transports: [inProcess.server], services: [TestService()])
          try await server.run()
        }

        group.addTask {
          try await withThrowingTaskGroup(of: Void.self) { clientGroup in
            let client = GRPCClient(transport: inProcess.client)
            clientGroup.addTask {
              try await client.run()
            }
            try await interopTestCase.makeTest().run(client: client)

            clientGroup.cancelAll()
          }
        }

        try await group.next()
        group.cancelAll()
      }
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testEmtyUnary() async throws {
    try await self.runInProcessTransport(interopTestCase: .emptyUnary)
  }

  func testLargeUnary() async throws {
    try await self.runInProcessTransport(interopTestCase: .largeUnary)
  }

  func testClientStreaming() async throws {
    try await self.runInProcessTransport(interopTestCase: .clientStreaming)
  }

  func testServerStreaming() async throws {
    try await self.runInProcessTransport(interopTestCase: .serverStreaming)
  }

  func testPingPong() async throws {
    try await self.runInProcessTransport(interopTestCase: .pingPong)
  }

  func testEmptyStream() async throws {
    try await self.runInProcessTransport(interopTestCase: .emptyStream)
  }

  func testCustomMetdata() async throws {
    try await self.runInProcessTransport(interopTestCase: .customMetadata)
  }

  func testStatusCodeAndMessage() async throws {
    try await self.runInProcessTransport(interopTestCase: .statusCodeAndMessage)
  }

  func testSpecialStatusMessage() async throws {
    try await self.runInProcessTransport(interopTestCase: .specialStatusMessage)
  }

  func testUnimplementedMethod() async throws {
    try await self.runInProcessTransport(interopTestCase: .unimplementedMethod)
  }

  func testUnimplementedService() async throws {
    try await self.runInProcessTransport(interopTestCase: .unimplementedService)
  }
}
