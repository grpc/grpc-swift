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
  private func makePipeline<Request, Response>(
    requests: Request.Type = Request.self,
    responses: Response.Type = Response.self,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    errorDelegate: ClientErrorDelegate? = nil,
    onCancel: @escaping (EventLoopPromise<Void>?) -> Void = { _ in XCTFail("Unexpected cancel") },
    onRequestPart: @escaping (ClientRequestPart<Request>, EventLoopPromise<Void>?) -> Void,
    onResponsePart: @escaping (ClientResponsePart<Response>) -> Void
  ) -> ClientInterceptorPipeline<Request, Response> {
    return ClientInterceptorPipeline(
      logger: self.clientLogger,
      eventLoop: EmbeddedEventLoop(),
      interceptors: interceptors,
      errorDelegate: errorDelegate,
      onCancel: onCancel,
      onRequestPart: onRequestPart,
      onResponsePart: onResponsePart
    )
  }

  func testEmptyPipeline() throws {
    var requestParts: [ClientRequestPart<String>] = []
    var responseParts: [ClientResponsePart<String>] = []

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
    pipeline.write(.metadata([:]), promise: nil)
    pipeline.write(.message("foo", .init(compress: false, flush: false)), promise: nil)
    pipeline.write(.end, promise: nil)

    XCTAssertEqual(requestParts.count, 3)
    XCTAssertEqual(requestParts[0].metadata, [:])
    let (message, metadata) = try assertNotNil(requestParts[1].message)
    XCTAssertEqual(message, "foo")
    XCTAssertEqual(metadata, .init(compress: false, flush: false))
    XCTAssertTrue(requestParts[2].isEnd)

    // Write some responses parts.
    pipeline.read(.metadata([:]))
    pipeline.read(.message("bar"))
    pipeline.read(.end(.ok, [:]))

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
      onResponsePart: {
        XCTAssertNotNil($0.error)
      }
    )

    // Fire an error; this should close the pipeline.
    struct DummyError: Error {}
    pipeline.read(.error(DummyError()))

    // We're closed, writes should fail.
    let writePromise = pipeline.eventLoop.makePromise(of: Void.self)
    pipeline.write(.end, promise: writePromise)
    XCTAssertThrowsError(try writePromise.futureResult.wait())

    // As should cancellation.
    let cancelPromise = pipeline.eventLoop.makePromise(of: Void.self)
    pipeline.cancel(promise: cancelPromise)
    XCTAssertThrowsError(try cancelPromise.futureResult.wait())

    // And reads should be ignored. (We only expect errors in the response handler.)
    pipeline.read(.metadata([:]))
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

    pipeline.write(.message("foo", .init(compress: false, flush: false)), promise: nil)
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
      pipeline.read(.error(error))
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
  var requestParts: [ClientRequestPart<Request>] = []
  var responseParts: [ClientResponsePart<Response>] = []

  override func write(
    _ part: ClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    self.requestParts.append(part)
    context.write(part, promise: promise)
  }

  override func read(
    _ part: ClientResponsePart<Response>,
    context: ClientInterceptorContext<Request, Response>
  ) {
    self.responseParts.append(part)
    context.read(part)
  }
}

/// An interceptor which reverses string request messages.
class StringRequestReverser: ClientInterceptor<String, String> {
  override func write(
    _ part: ClientRequestPart<String>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<String, String>
  ) {
    switch part {
    case let .message(value, metadata):
      context.write(.message(String(value.reversed()), metadata), promise: promise)
    default:
      context.write(part, promise: promise)
    }
  }
}

// MARK: - Request/Response part helpers

extension ClientRequestPart {
  var metadata: HPACKHeaders? {
    switch self {
    case let .metadata(headers):
      return headers
    case .message, .end:
      return nil
    }
  }

  var message: (Request, Metadata)? {
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

extension ClientResponsePart {
  var metadata: HPACKHeaders? {
    switch self {
    case let .metadata(headers):
      return headers
    case .message, .end, .error:
      return nil
    }
  }

  var message: Response? {
    switch self {
    case let .message(response):
      return response
    case .metadata, .end, .error:
      return nil
    }
  }

  var end: (GRPCStatus, HPACKHeaders)? {
    switch self {
    case let .end(status, trailers):
      return (status, trailers)
    case .metadata, .message, .error:
      return nil
    }
  }

  var error: Error? {
    switch self {
    case let .error(error):
      return error
    case .metadata, .message, .end:
      return nil
    }
  }
}
