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

  #if swift(>=5.8)  // Compiling these tests fails in 5.7
  func testClientInterceptor() async throws {
    var serviceContext = ServiceContext.topLevel
    let traceIDString = UUID().uuidString
    let interceptor = ClientTracingInterceptor(emitEventOnEachWrite: false)
    let (stream, continuation) = AsyncStream<String>.makeStream()
    serviceContext.traceID = traceIDString

    try await ServiceContext.withValue(serviceContext) {
      let methodDescriptor = MethodDescriptor(
        service: "TracingInterceptorTests",
        method: "testClientInterceptor"
      )
      let response = try await interceptor.intercept(
        request: .init(producer: { writer in
          try await writer.write(contentsOf: ["request1"])
          try await writer.write(contentsOf: ["request2"])
        }),
        context: .init(descriptor: methodDescriptor)
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])

        // Write into the response stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: continuation))
        try await stream.producer(writer)
        continuation.finish()

        return .init(
          metadata: [],
          bodyParts: .init(
            wrapping: AsyncStream<ClientResponse.Stream.Contents.BodyPart> { cont in
              cont.yield(.message(["response"]))
              cont.finish()
            }
          )
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
      var message = try await messages.next()
      XCTAssertEqual(message, ["response"])
      message = try await messages.next()
      XCTAssertNil(message)

      let tracer = InstrumentationSystem.tracer as! TestTracer
      XCTAssertEqual(
        tracer.getEventsForTestSpan(ofOperationName: methodDescriptor.fullyQualifiedMethod).map {
          $0.name
        },
        [
          "Request started",
          "Received response end",
        ]
      )
    }
  }

  func testClientInterceptorAllEventsRecorded() async throws {
    let methodDescriptor = MethodDescriptor(
      service: "TracingInterceptorTests",
      method: "testClientInterceptorAllEventsRecorded"
    )
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
        context: .init(descriptor: methodDescriptor)
      ) { stream, _ in
        // Assert the metadata contains the injected context key-value.
        XCTAssertEqual(stream.metadata, ["trace-id": "\(traceIDString)"])

        // Write into the response stream to make sure the `producer` closure's called.
        let writer = RPCWriter(wrapping: TestWriter(streamContinuation: continuation))
        try await stream.producer(writer)
        continuation.finish()

        return .init(
          metadata: [],
          bodyParts: .init(
            wrapping: AsyncStream<ClientResponse.Stream.Contents.BodyPart> { cont in
              cont.yield(.message(["response"]))
              cont.finish()
            }
          )
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
      var message = try await messages.next()
      XCTAssertEqual(message, ["response"])
      message = try await messages.next()
      XCTAssertNil(message)

      let tracer = InstrumentationSystem.tracer as! TestTracer
      XCTAssertEqual(
        tracer.getEventsForTestSpan(ofOperationName: methodDescriptor.fullyQualifiedMethod).map {
          $0.name
        },
        [
          "Request started",
          // Recorded when `request1` is sent
          "Sending request part",
          "Sent request part",
          // Recorded when `request2` is sent
          "Sending request part",
          "Sent request part",
          // Recorded after all request parts have been sent
          "Request end",
          // Recorded when receiving response part
          "Received response part",
          // Recorded at end of response
          "Received response end",
        ]
      )
    }
  }
  #endif  // swift >= 5.7

  func testServerInterceptorErrorResponse() async throws {
    let methodDescriptor = MethodDescriptor(
      service: "TracingInterceptorTests",
      method: "testServerInterceptorErrorResponse"
    )
    let interceptor = ServerTracingInterceptor(emitEventOnEachWrite: false)
    let response = try await interceptor.intercept(
      request: .init(single: .init(metadata: ["trace-id": "some-trace-id"], message: [])),
      context: .init(descriptor: methodDescriptor)
    ) { _, _ in
      ServerResponse.Stream<String>(error: .init(code: .unknown, message: "Test error"))
    }
    XCTAssertThrowsError(try response.accepted.get())

    let tracer = InstrumentationSystem.tracer as! TestTracer
    XCTAssertEqual(
      tracer.getEventsForTestSpan(ofOperationName: methodDescriptor.fullyQualifiedMethod).map {
        $0.name
      },
      [
        "Received request start",
        "Received request end",
        "Sent error response",
      ]
    )
  }

  func testServerInterceptor() async throws {
    let methodDescriptor = MethodDescriptor(
      service: "TracingInterceptorTests",
      method: "testServerInterceptor"
    )
    let (stream, continuation) = AsyncStream<String>.makeStream()
    let interceptor = ServerTracingInterceptor(emitEventOnEachWrite: false)
    let response = try await interceptor.intercept(
      request: .init(single: .init(metadata: ["trace-id": "some-trace-id"], message: [])),
      context: .init(descriptor: methodDescriptor)
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
      tracer.getEventsForTestSpan(ofOperationName: methodDescriptor.fullyQualifiedMethod).map {
        $0.name
      },
      [
        "Received request start",
        "Received request end",
        "Sent response end",
      ]
    )
  }

  func testServerInterceptorAllEventsRecorded() async throws {
    let methodDescriptor = MethodDescriptor(
      service: "TracingInterceptorTests",
      method: "testServerInterceptorAllEventsRecorded"
    )
    let (stream, continuation) = AsyncStream<String>.makeStream()
    let interceptor = ServerTracingInterceptor(emitEventOnEachWrite: true)
    let response = try await interceptor.intercept(
      request: .init(single: .init(metadata: ["trace-id": "some-trace-id"], message: [])),
      context: .init(descriptor: methodDescriptor)
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
      tracer.getEventsForTestSpan(ofOperationName: methodDescriptor.fullyQualifiedMethod).map {
        $0.name
      },
      [
        "Received request start",
        "Received request end",
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
