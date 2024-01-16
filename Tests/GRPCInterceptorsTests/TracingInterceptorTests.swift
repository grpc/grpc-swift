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
import Tracing
import XCTest

@testable import GRPCInterceptors

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class TracingInterceptorTests: TracingTestCase {
  func testClientInterceptor() async throws {
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let interceptor = ClientTracingInterceptor()
    
    serviceContext.traceID = traceIDString
    try await ServiceContext.withValue(serviceContext) {
      let response = try await interceptor.intercept(
        request: .init(producer: { writer in try await writer.write(["request"])}),
        context: .init(descriptor: .init(service: "foo", method: "bar"))) { stream, _ in
          XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])
          return .init(metadata: [], bodyParts: .init(wrapping: AsyncStream(unfolding: { .message(["response"]) })))
        }
      
      var messages = response.messages.makeAsyncIterator()
      let message = try await messages.next()
      XCTAssertEqual(message, ["response"])
    }
  }

  func testServerInterceptor() async throws {
    let interceptor = ServerTracingInterceptor()
    let response = try await interceptor.intercept(
      request: .init(single: .init(metadata: [], message: [])),
      context: .init(descriptor: .init(service: "foo", method: "bar"))) { _, _ in
        return .init(accepted: .success(.init(metadata: [], producer: { writer in
          guard let serviceContext = ServiceContext.current else {
            XCTFail("There should be a service context present.")
            return []
          }

          let traceID = serviceContext.traceID
          XCTAssertEqual("some-trace-id", traceID)

          try await writer.write("response")
          return []
        })))
      }
  }
}
