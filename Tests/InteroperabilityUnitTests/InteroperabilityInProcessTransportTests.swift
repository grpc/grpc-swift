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

final class InteroperabilityInProcessTransportTests: XCTestCase {
  func runInProcessTransport(
    interopTest: @escaping @Sendable (GRPCClient) async throws -> Void
  ) async throws {
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
  }

  func testEmtyUnary() async throws {
    let emptyUnaryTestCase = EmptyUnary()
    do {
      try await runInProcessTransport(interopTest: emptyUnaryTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testLargeUnary() async throws {
    let largeUnaryTestCase = LargeUnary()
    do {
      try await runInProcessTransport(interopTest: largeUnaryTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testClientStreaming() async throws {
    let clientStreamingTestCase = ClientStreaming()
    do {
      try await runInProcessTransport(interopTest: clientStreamingTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testServerStreaming() async throws {
    let serverStreamingTestCase = ServerStreaming()
    do {
      try await runInProcessTransport(interopTest: serverStreamingTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testPingPong() async throws {
    let pingPongTestCase = PingPong()
    do {
      try await runInProcessTransport(interopTest: pingPongTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testEmptyStream() async throws {
    let emptyStreamTestCase = EmptyStream()
    do {
      try await runInProcessTransport(interopTest: emptyStreamTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testCustomMetdata() async throws {
    let customMetadataTestCase = CustomMetadata()
    do {
      try await runInProcessTransport(interopTest: customMetadataTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testStatusCodeAndMessage() async throws {
    let statusCodeAndMessageTestCase = StatusCodeAndMessage()
    do {
      try await runInProcessTransport(interopTest: statusCodeAndMessageTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testSpecialStatusMessage() async throws {
    let specialStatusMessageTestCase = StatusCodeAndMessage()
    do {
      try await runInProcessTransport(interopTest: specialStatusMessageTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testUnimplementedMethod() async throws {
    let unimplementedMethodTestCase = StatusCodeAndMessage()
    do {
      try await runInProcessTransport(interopTest: unimplementedMethodTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }

  func testUnimplementedService() async throws {
    let unimplementedServiceTestCase = StatusCodeAndMessage()
    do {
      try await runInProcessTransport(interopTest: unimplementedServiceTestCase.run)
    } catch let error as AssertionFailure {
      XCTFail(error.message)
    }
  }
}
