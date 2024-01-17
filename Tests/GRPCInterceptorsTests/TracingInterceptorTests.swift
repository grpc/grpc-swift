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
final class TracingInterceptorTests: XCTestCase {
  override class func setUp() {
    InstrumentationSystem.bootstrap(TestTracer())
  }

  func testClientInterceptor() async throws {
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let interceptor = ClientTracingInterceptor(emitEventOnEachWrite: false)
    let (stream, continuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    try await ServiceContext.withValue(serviceContext) {
      let response = try await interceptor.intercept(
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request1"])
          try await writer.write(contentsOf: ["request2"])
        }),
        context: .init(descriptor: .init(service: "foo", method: "bar"))
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])

        // Write into the response stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: continuation))
        try await stream.producer(writer)
        continuation.finish()

        return .init(
          metadata: [],
          bodyParts: .init(wrapping: AsyncStream(unfolding: { .message(["response"]) }))
        )
      }

      var streamIterator = stream.makeAsyncIterator()
      var element = await streamIterator.next()
      XCTAssertEqual(element, "request1")
      element = await streamIterator.next()
      XCTAssertEqual(element, "request2")
      element = await streamIterator.next()
      XCTAssertNil(element)

      var messages = response.messages.makeAsyncIterator()
      let message = try await messages.next()
      XCTAssertEqual(message, ["response"])

      let tracer = InstrumentationSystem.tracer as! TestTracer
      XCTAssertEqual(
        tracer.latestSpanEvents.map { $0.name },
        [
          "Request started",
          "Received response end",
        ]
      )
    }
  }

  func testClientInterceptorAllEventsRecorded() async throws {
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let interceptor = ClientTracingInterceptor(emitEventOnEachWrite: true)
    let (stream, continuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    try await ServiceContext.withValue(serviceContext) {
      let response = try await interceptor.intercept(
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request1"])
          try await writer.write(contentsOf: ["request2"])
        }),
        context: .init(descriptor: .init(service: "foo", method: "bar"))
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])

        // Write into the response stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: continuation))
        try await stream.producer(writer)
        continuation.finish()

        return .init(
          metadata: [],
          bodyParts: .init(wrapping: AsyncStream(unfolding: { .message(["response"]) }))
        )
      }

      var streamIterator = stream.makeAsyncIterator()
      var element = await streamIterator.next()
      XCTAssertEqual(element, "request1")
      element = await streamIterator.next()
      XCTAssertEqual(element, "request2")
      element = await streamIterator.next()
      XCTAssertNil(element)

      var messages = response.messages.makeAsyncIterator()
      let message = try await messages.next()
      XCTAssertEqual(message, ["response"])

      let tracer = InstrumentationSystem.tracer as! TestTracer
      XCTAssertEqual(
        tracer.latestSpanEvents.map { $0.name },
        [
          "Request started",
          // Recorded when `request1` is sent
          "Sending request part",
          "Sent request part",
          // Recorded when `request2` is sent
          "Sending request part",
          "Sent request part",
          // Recorded at end of `producer`
          "Received response end",
        ]
      )
    }
  }

  func testServerInterceptorErrorResponse() async throws {
    let interceptor = ServerTracingInterceptor(emitEventOnEachWrite: false)
    let response = try await interceptor.intercept(
      request: .init(single: .init(metadata: ["trace-id": "some-trace-id"], message: [])),
      context: .init(descriptor: .init(service: "foo", method: "bar"))
    ) { _, _ in
      ServerResponse.Stream<String>(error: .init(code: .unknown, message: "Test error"))
    }
    XCTAssertThrowsError(try response.accepted.get())

    let tracer = InstrumentationSystem.tracer as! TestTracer
    XCTAssertEqual(
      tracer.latestSpanEvents.map { $0.name },
      [
        "Received request",
        "Sent error response",
      ]
    )
  }

  func testServerInterceptor() async throws {
    let (stream, continuation) = AsyncStream<String>.makeStream()
    let interceptor = ServerTracingInterceptor(emitEventOnEachWrite: false)
    let response = try await interceptor.intercept(
      request: .init(single: .init(metadata: ["trace-id": "some-trace-id"], message: [])),
      context: .init(descriptor: .init(service: "foo", method: "bar"))
    ) { _, _ in
      { [serviceContext = ServiceContext.current] in
        return ServerResponse.Stream<String>(
          accepted: .success(
            .init(
              metadata: [],
              producer: { writer in
                guard let serviceContext else {
                  XCTFail("There should be a service context present.")
                  return ["Result": "Test failed"]
                }

                let traceID = serviceContext.traceID
                XCTAssertEqual("some-trace-id", traceID)

                try await writer.write("response1")
                try await writer.write("response2")

                return ["Result": "Trailing metadata"]
              }
            )
          )
        )
      }()
    }

    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: continuation))
    )
    continuation.finish()
    XCTAssertEqual(trailingMetadata, ["Result": "Trailing metadata"])

    var streamIterator = stream.makeAsyncIterator()
    var element = await streamIterator.next()
    XCTAssertEqual(element, "response1")
    element = await streamIterator.next()
    XCTAssertEqual(element, "response2")
    element = await streamIterator.next()
    XCTAssertNil(element)

    let tracer = InstrumentationSystem.tracer as! TestTracer
    XCTAssertEqual(
      tracer.latestSpanEvents.map { $0.name },
      [
        "Received request",
        "Sent response end",
      ]
    )
  }

  func testServerInterceptorAllEventsRecorded() async throws {
    let (stream, continuation) = AsyncStream<String>.makeStream()
    let interceptor = ServerTracingInterceptor(emitEventOnEachWrite: true)
    let response = try await interceptor.intercept(
      request: .init(single: .init(metadata: ["trace-id": "some-trace-id"], message: [])),
      context: .init(descriptor: .init(service: "foo", method: "bar"))
    ) { _, _ in
      { [serviceContext = ServiceContext.current] in
        return ServerResponse.Stream<String>(
          accepted: .success(
            .init(
              metadata: [],
              producer: { writer in
                guard let serviceContext else {
                  XCTFail("There should be a service context present.")
                  return ["Result": "Test failed"]
                }

                let traceID = serviceContext.traceID
                XCTAssertEqual("some-trace-id", traceID)

                try await writer.write("response1")
                try await writer.write("response2")

                return ["Result": "Trailing metadata"]
              }
            )
          )
        )
      }()
    }

    let responseContents = try response.accepted.get()
    let trailingMetadata = try await responseContents.producer(
      RPCWriter(wrapping: TestWriter(streamContinuation: continuation))
    )
    continuation.finish()
    XCTAssertEqual(trailingMetadata, ["Result": "Trailing metadata"])

    var streamIterator = stream.makeAsyncIterator()
    var element = await streamIterator.next()
    XCTAssertEqual(element, "response1")
    element = await streamIterator.next()
    XCTAssertEqual(element, "response2")
    element = await streamIterator.next()
    XCTAssertNil(element)

    let tracer = InstrumentationSystem.tracer as! TestTracer
    XCTAssertEqual(
      tracer.latestSpanEvents.map { $0.name },
      [
        "Received request",
        // Recorded when `response1` is sent
        "Sending response part",
        "Sent response part",
        // Recorded when `response2` is sent
        "Sending response part",
        "Sent response part",
        // Recorded when we're done sending response
        "Sent response end",
      ]
    )
  }
}
