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

final class InProcessInteroperabilityTests: XCTestCase {
  func runInProcessTransport(
    interopTest: @escaping (GRPCClient) async throws -> Void
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
            try await interopTest(client)

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
    let emptyUnaryTestCase = InteroperabilityTestCase.emptyUnary.makeTest()
    try await runInProcessTransport(interopTest: emptyUnaryTestCase.run)
  }

  func testLargeUnary() async throws {
    let largeUnaryTestCase = LargeUnary()
    try await runInProcessTransport(interopTest: largeUnaryTestCase.run)
  }

  func testClientStreaming() async throws {
    let clientStreamingTestCase = ClientStreaming()
    try await runInProcessTransport(interopTest: clientStreamingTestCase.run)
  }

  func testServerStreaming() async throws {
    let serverStreamingTestCase = ServerStreaming()
    try await runInProcessTransport(interopTest: serverStreamingTestCase.run)
  }

  func testPingPong() async throws {
    let pingPongTestCase = PingPong()
    try await runInProcessTransport(interopTest: pingPongTestCase.run)
  }

  func testEmptyStream() async throws {
    let emptyStreamTestCase = EmptyStream()
    try await runInProcessTransport(interopTest: emptyStreamTestCase.run)
  }

  func testCustomMetdata() async throws {
    let customMetadataTestCase = CustomMetadata()
    try await runInProcessTransport(interopTest: customMetadataTestCase.run)
  }

  func testStatusCodeAndMessage() async throws {
    let statusCodeAndMessageTestCase = StatusCodeAndMessage()
    try await runInProcessTransport(interopTest: statusCodeAndMessageTestCase.run)
  }

  func testSpecialStatusMessage() async throws {
    let specialStatusMessageTestCase = StatusCodeAndMessage()
    try await runInProcessTransport(interopTest: specialStatusMessageTestCase.run)
  }

  func testUnimplementedMethod() async throws {
    let unimplementedMethodTestCase = StatusCodeAndMessage()
    try await runInProcessTransport(interopTest: unimplementedMethodTestCase.run)
  }

  func testUnimplementedService() async throws {
    let unimplementedServiceTestCase = StatusCodeAndMessage()
    try await runInProcessTransport(interopTest: unimplementedServiceTestCase.run)
  }
}
