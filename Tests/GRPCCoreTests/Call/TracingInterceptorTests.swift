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
import GRPCInterceptors
import Tracing
import XCTest

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class ClientTracingInterceptorTests: TracingTestCase {
  func testClientInterceptor() async throws {
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    serviceContext.traceID = traceIDString
    try await ServiceContext.withValue(serviceContext) {
      let tester = ClientRPCExecutorTestHarness(server: .echo)
      try await tester.unary(
        request: ClientRequest.Single(message: [1, 2, 3], metadata: ["foo": "bar"]),
        interceptors: [ClientTracingInterceptor()]
      ) { response in
        XCTAssertEqual(
          response.metadata,
          [
            "foo": "bar",
            "trace-id": "\(traceIDString)",
          ]
        )
        XCTAssertEqual(try response.message, [1, 2, 3])
      }

      XCTAssertEqual(tester.clientStreamsOpened, 1)
      XCTAssertEqual(tester.serverStreamsAccepted, 1)
    }
  }

  func testServerInterceptor() async throws {
    let harness = ServerRPCExecutorTestHarness(interceptors: [ServerTracingInterceptor()])
    try await harness.execute(
      deserializer: IdentityDeserializer(),
      serializer: IdentitySerializer()
    ) { request in
      guard let serviceContext = ServiceContext.current else {
        XCTFail("There should be a service context present.")
        return .init(
          error: .init(
            status: .init(
              code: .failedPrecondition,
              message: "There should be a service context present."
            )
          )!
        )
      }

      let traceID = serviceContext.traceID
      XCTAssertEqual("some-trace-id", traceID)

      return .init(accepted: .success(.init(metadata: [], producer: { _ in [] })))
    } producer: { inbound in
      try await inbound.write(.metadata(["trace-id": "some-trace-id"]))
      inbound.finish()
    } consumer: { _ in
    }
  }
}
