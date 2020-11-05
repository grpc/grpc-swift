/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
@testable import GRPC
import Logging
import NIO
import NIOHPACK
import XCTest

class ClientInterceptorPipelineTests: GRPCTestCase {
  override func setUp() {
    super.setUp()
    self.embeddedEventLoop = EmbeddedEventLoop()
  }

  private var embeddedEventLoop: EmbeddedEventLoop!

  private func makePipeline<Request, Response>(
    requests: Request.Type = Request.self,
    responses: Response.Type = Response.self,
    details: CallDetails? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    errorDelegate: ClientErrorDelegate? = nil,
    onError: @escaping (Error) -> Void = { _ in },
    onCancel: @escaping (EventLoopPromise<Void>?) -> Void = { _ in },
    onRequestPart: @escaping (GRPCClientRequestPart<Request>, EventLoopPromise<Void>?) -> Void,
    onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) -> ClientInterceptorPipeline<Request, Response> {
    return ClientInterceptorPipeline(
      eventLoop: self.embeddedEventLoop,
      details: details ?? self.makeCallDetails(),
      interceptors: interceptors,
      errorDelegate: errorDelegate,
      onError: onError,
      onCancel: onCancel,
      onRequestPart: onRequestPart,
      onResponsePart: onResponsePart
    )
  }

  private func makeCallDetails(timeLimit: TimeLimit = .none) -> CallDetails {
    return CallDetails(
      type: .unary,
      path: "ignored",
      authority: "ignored",
      scheme: "ignored",
      options: CallOptions(timeLimit: timeLimit, logger: self.clientLogger)
    )
  }

  func testEmptyPipeline() throws {
    var requestParts: [GRPCClientRequestPart<String>] = []
    var responseParts: [GRPCClientResponsePart<String>] = []

    let pipeline = self.makePipeline(
      requests: String.self,
      responses: String.self,
      onRequestPart: { request, promise in
        requestParts.append(request)
        XCTAssertNil(promise)
      },
      onResponsePart: { responseParts.append($0) }
    )

    // Write some request parts.
    pipeline.send(.metadata([:]), promise: nil)
    pipeline.send(.message("foo", .init(compress: false, flush: false)), promise: nil)
    pipeline.send(.end, promise: nil)

    XCTAssertEqual(requestParts.count, 3)
    XCTAssertEqual(requestParts[0].metadata, [:])
    let (message, metadata) = try assertNotNil(requestParts[1].message)
    XCTAssertEqual(message, "foo")
    XCTAssertEqual(metadata, .init(compress: false, flush: false))
    XCTAssertTrue(requestParts[2].isEnd)

    // Write some responses parts.
    pipeline.receive(.metadata([:]))
    pipeline.receive(.message("bar"))
    pipeline.receive(.end(.ok, [:]))

    XCTAssertEqual(responseParts.count, 3)
    XCTAssertEqual(responseParts[0].metadata, [:])
    XCTAssertEqual(responseParts[1].message, "bar")
    let (status, trailers) = try assertNotNil(responseParts[2].end)
    XCTAssertEqual(status, .ok)
    XCTAssertEqual(trailers, [:])
  }

  func testPipelineWhenClosed() throws {
    let pipeline = self.makePipeline(
      requests: String.self,
      responses: String.self,
      onRequestPart: { _, promise in
        XCTAssertNil(promise)
      },
      onResponsePart: { _ in }
    )

    // Fire an error; this should close the pipeline.
    struct DummyError: Error {}
    pipeline.errorCaught(DummyError())

    // We're closed, writes should fail.
    let writePromise = pipeline.eventLoop.makePromise(of: Void.self)
    pipeline.send(.end, promise: writePromise)
    XCTAssertThrowsError(try writePromise.futureResult.wait())

    // As should cancellation.
    let cancelPromise = pipeline.eventLoop.makePromise(of: Void.self)
    pipeline.cancel(promise: cancelPromise)
    XCTAssertThrowsError(try cancelPromise.futureResult.wait())

    // And reads should be ignored. (We only expect errors in the response handler.)
    pipeline.receive(.metadata([:]))
  }

  func testPipelineWithTimeout() throws {
    var cancelled = false
    var timedOut = false

    class FailOnCancel<Request, Response>: ClientInterceptor<Request, Response> {
      override func cancel(
        promise: EventLoopPromise<Void>?,
        context: ClientInterceptorContext<Request, Response>
      ) {
        XCTFail("Unexpected cancellation")
        context.cancel(promise: promise)
      }
    }

    let deadline = NIODeadline.uptimeNanoseconds(100)
    let pipeline = self.makePipeline(
      requests: String.self,
      responses: String.self,
      details: self.makeCallDetails(timeLimit: .deadline(deadline)),
      interceptors: [FailOnCancel()],
      onError: { error in
        assertThat(error, .is(.instanceOf(GRPCError.RPCTimedOut.self)))
        assertThat(timedOut, .is(false))
        timedOut = true
      },
      onCancel: { promise in
        assertThat(cancelled, .is(false))
        cancelled = true
        // We don't expect a promise: this cancellation is fired by the pipeline.
        assertThat(promise, .is(.nil()))
      },
      onRequestPart: { _, _ in
        XCTFail("Unexpected request part")
      },
      onResponsePart: { _ in
        XCTFail("Unexpected response part")
      }
    )

    // Trigger the timeout.
    self.embeddedEventLoop.advanceTime(to: deadline)
    assertThat(timedOut, .is(true))

    // We'll receive a cancellation; we only get this 'onCancel' callback. We'll fail in the
    // interceptor if a cancellation is received.
    assertThat(cancelled, .is(true))

    // Pipeline should be torn down. Writes and cancellation should fail.
    let p1 = pipeline.eventLoop.makePromise(of: Void.self)
    pipeline.send(.end, promise: p1)
    assertThat(try p1.futureResult.wait(), .throws(.instanceOf(GRPCError.AlreadyComplete.self)))

    let p2 = pipeline.eventLoop.makePromise(of: Void.self)
    pipeline.cancel(promise: p2)
    assertThat(try p2.futureResult.wait(), .throws(.instanceOf(GRPCError.AlreadyComplete.self)))

    // Reads should be ignored too. (We'll fail in `onRequestPart` if this goes through.)
    pipeline.receive(.metadata([:]))
  }

  func testTimeoutIsCancelledOnCompletion() throws {
    let deadline = NIODeadline.uptimeNanoseconds(100)
    var cancellations = 0

    let pipeline = self.makePipeline(
      requests: String.self,
      responses: String.self,
      details: self.makeCallDetails(timeLimit: .deadline(deadline)),
      onCancel: { promise in
        assertThat(cancellations, .is(0))
        cancellations += 1
        // We don't expect a promise: this cancellation is fired by the pipeline.
        assertThat(promise, .is(.nil()))
      },
      onRequestPart: { _, _ in
        XCTFail("Unexpected request part")
      },
      onResponsePart: { part in
        // We only expect the end.
        assertThat(part.end, .is(.notNil()))
      }
    )

    // Read the end part.
    pipeline.receive(.end(.ok, [:]))
    // Just a single cancellation.
    assertThat(cancellations, .is(1))

    // Pass the deadline.
    self.embeddedEventLoop.advanceTime(to: deadline)
    // We should still have just the one cancellation.
    assertThat(cancellations, .is(1))
  }

  func testPipelineWithInterceptor() throws {
    // We're not testing much here, just that the interceptors are in the right order, from outbound
    // to inbound.
    let recorder = RecordingInterceptor<String, String>()
    let pipeline = self.makePipeline(
      interceptors: [StringRequestReverser(), recorder],
      onRequestPart: { _, _ in },
      onResponsePart: { _ in }
    )

    pipeline.send(.message("foo", .init(compress: false, flush: false)), promise: nil)
    XCTAssertEqual(recorder.requestParts.count, 1)
    let (message, _) = try assertNotNil(recorder.requestParts[0].message)
    XCTAssertEqual(message, "oof")
  }

  func testErrorDelegateIsCalled() throws {
    class Delegate: ClientErrorDelegate {
      let expectedError: GRPCError.InvalidState
      let file: StaticString?
      let line: Int?

      init(
        expected: GRPCError.InvalidState,
        file: StaticString?,
        line: Int?
      ) {
        precondition(file == nil && line == nil || file != nil && line != nil)
        self.expectedError = expected
        self.file = file
        self.line = line
      }

      func didCatchError(_ error: Error, logger: Logger, file: StaticString, line: Int) {
        XCTAssertEqual(error as? GRPCError.InvalidState, self.expectedError)

        // Check the file and line, if expected.
        if let expectedFile = self.file, let expectedLine = self.line {
          XCTAssertEqual("\(file)", "\(expectedFile)") // StaticString isn't Equatable
          XCTAssertEqual(line, expectedLine)
        }
      }
    }

    func doTest(withDelegate delegate: Delegate, error: Error) {
      let pipeline = self.makePipeline(
        requests: String.self,
        responses: String.self,
        errorDelegate: delegate,
        onRequestPart: { _, _ in },
        onResponsePart: { _ in }
      )
      pipeline.errorCaught(error)
    }

    let invalidState = GRPCError.InvalidState("invalid state")
    let withContext = GRPCError.WithContext(invalidState)

    doTest(
      withDelegate: .init(expected: invalidState, file: withContext.file, line: withContext.line),
      error: withContext
    )

    doTest(
      withDelegate: .init(expected: invalidState, file: nil, line: nil),
      error: invalidState
    )
  }
}

// MARK: - Test Interceptors

/// A simple interceptor which records and then forwards and request and response parts it sees.
class RecordingInterceptor<Request, Response>: ClientInterceptor<Request, Response> {
  var requestParts: [GRPCClientRequestPart<Request>] = []
  var responseParts: [GRPCClientResponsePart<Response>] = []

  override func send(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    self.requestParts.append(part)
    context.send(part, promise: promise)
  }

  override func receive(
    _ part: GRPCClientResponsePart<Response>,
    context: ClientInterceptorContext<Request, Response>
  ) {
    self.responseParts.append(part)
    context.receive(part)
  }
}

/// An interceptor which reverses string request messages.
class StringRequestReverser: ClientInterceptor<String, String> {
  override func send(
    _ part: GRPCClientRequestPart<String>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<String, String>
  ) {
    switch part {
    case let .message(value, metadata):
      context.send(.message(String(value.reversed()), metadata), promise: promise)
    default:
      context.send(part, promise: promise)
    }
  }
}

// MARK: - Request/Response part helpers

extension GRPCClientRequestPart {
  var metadata: HPACKHeaders? {
    switch self {
    case let .metadata(headers):
      return headers
    case .message, .end:
      return nil
    }
  }

  var message: (Request, MessageMetadata)? {
    switch self {
    case let .message(request, metadata):
      return (request, metadata)
    case .metadata, .end:
      return nil
    }
  }

  var isEnd: Bool {
    switch self {
    case .end:
      return true
    case .metadata, .message:
      return false
    }
  }
}

extension GRPCClientResponsePart {
  var metadata: HPACKHeaders? {
    switch self {
    case let .metadata(headers):
      return headers
    case .message, .end:
      return nil
    }
  }

  var message: Response? {
    switch self {
    case let .message(response):
      return response
    case .metadata, .end:
      return nil
    }
  }

  var end: (GRPCStatus, HPACKHeaders)? {
    switch self {
    case let .end(status, trailers):
      return (status, trailers)
    case .metadata, .message:
      return nil
    }
  }
}
