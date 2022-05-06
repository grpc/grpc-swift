/*
 * Copyright 2018, gRPC Authors All rights reserved.
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
import Dispatch
import EchoModel
import Foundation
@testable import GRPC
import NIOCore
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import XCTest

let thrownError = GRPCStatus(code: .internalError, message: "expected error")
let transformedError = GRPCStatus(code: .aborted, message: "transformed error")
let transformedMetadata = HPACKHeaders([("transformed", "header")])

// Motivation for two different providers: Throwing immediately causes the event observer future (in the
// client-streaming and bidi-streaming cases) to throw immediately, _before_ the corresponding handler has even added
// to the channel. We want to test that case as well as the one where we throw only _after_ the handler has been added
// to the channel.
class ImmediateThrowingEchoProvider: Echo_EchoProvider {
  var interceptors: Echo_EchoServerInterceptorFactoryProtocol? { return nil }

  func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    return context.eventLoop.makeFailedFuture(thrownError)
  }

  func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    return context.eventLoop.makeFailedFuture(thrownError)
  }

  func collect(context: UnaryResponseCallContext<Echo_EchoResponse>)
    -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeFailedFuture(thrownError)
  }

  func update(context: StreamingResponseCallContext<Echo_EchoResponse>)
    -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeFailedFuture(thrownError)
  }
}

extension EventLoop {
  func makeFailedFuture<T>(_ error: Error, delay: TimeInterval) -> EventLoopFuture<T> {
    return self.scheduleTask(in: .nanoseconds(Int64(delay * 1000 * 1000 * 1000))) { () }
      .futureResult
      .flatMapThrowing { _ -> T in throw error }
  }
}

/// See `ImmediateThrowingEchoProvider`.
class DelayedThrowingEchoProvider: Echo_EchoProvider {
  let interceptors: Echo_EchoServerInterceptorFactoryProtocol? = nil

  func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    return context.eventLoop.makeFailedFuture(thrownError, delay: 0.01)
  }

  func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    return context.eventLoop.makeFailedFuture(thrownError, delay: 0.01)
  }

  func collect(context: UnaryResponseCallContext<Echo_EchoResponse>)
    -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeFailedFuture(thrownError, delay: 0.01)
  }

  func update(context: StreamingResponseCallContext<Echo_EchoResponse>)
    -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeFailedFuture(thrownError, delay: 0.01)
  }
}

/// Ensures that fulfilling the status promise (where possible) with an error yields the same result as failing the future.
class ErrorReturningEchoProvider: ImmediateThrowingEchoProvider {
  // There's no status promise to fulfill for unary calls (only the response promise), so that case is omitted.

  override func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    return context.eventLoop.makeSucceededFuture(thrownError)
  }

  override func collect(context: UnaryResponseCallContext<Echo_EchoResponse>)
    -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeSucceededFuture({ _ in
      context.responseStatus = thrownError
      context.responsePromise.succeed(Echo_EchoResponse())
    })
  }

  override func update(context: StreamingResponseCallContext<Echo_EchoResponse>)
    -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeSucceededFuture({ _ in
      context.statusPromise.succeed(thrownError)
    })
  }
}

private class ErrorTransformingDelegate: ServerErrorDelegate {
  func transformRequestHandlerError(
    _ error: Error,
    headers: HPACKHeaders
  ) -> GRPCStatusAndTrailers? {
    return GRPCStatusAndTrailers(status: transformedError, trailers: transformedMetadata)
  }
}

class ServerThrowingTests: EchoTestCaseBase {
  var expectedError: GRPCStatus { return thrownError }
  var expectedMetadata: HPACKHeaders? {
    return HPACKHeaders([("grpc-status", "13"), ("grpc-message", "expected error")])
  }

  override func makeEchoProvider() -> Echo_EchoProvider { return ImmediateThrowingEchoProvider() }
}

class ServerDelayedThrowingTests: ServerThrowingTests {
  override func makeEchoProvider() -> Echo_EchoProvider { return DelayedThrowingEchoProvider() }
}

class ClientThrowingWhenServerReturningErrorTests: ServerThrowingTests {
  override func makeEchoProvider() -> Echo_EchoProvider { return ErrorReturningEchoProvider() }
}

class ServerErrorTransformingTests: ServerThrowingTests {
  override var expectedError: GRPCStatus { return transformedError }
  override var expectedMetadata: HPACKHeaders? {
    return HPACKHeaders([("grpc-status", "10"), ("grpc-message", "transformed error"),
                         ("transformed", "header")])
  }

  override func makeErrorDelegate() -> ServerErrorDelegate? { return ErrorTransformingDelegate() }
}

extension ServerThrowingTests {
  func testUnary() throws {
    let call = client.get(Echo_EchoRequest(text: "foo"))
    XCTAssertEqual(self.expectedError, try call.status.wait())
    let trailers = try call.trailingMetadata.wait()
    if let expected = self.expectedMetadata {
      for (name, value, _) in expected {
        XCTAssertTrue(trailers[name].contains(value))
      }
    }
    XCTAssertThrowsError(try call.response.wait()) {
      XCTAssertEqual(expectedError, $0 as? GRPCStatus)
    }
  }

  func testClientStreaming() throws {
    let call = client.collect()
    // This is racing with the server error; it might fail, it might not.
    try? call.sendEnd().wait()
    XCTAssertEqual(self.expectedError, try call.status.wait())
    let trailers = try call.trailingMetadata.wait()
    if let expected = self.expectedMetadata {
      for (name, value, _) in expected {
        XCTAssertTrue(trailers[name].contains(value))
      }
    }

    if type(of: self.makeEchoProvider()) != ErrorReturningEchoProvider.self {
      // With `ErrorReturningEchoProvider` we actually _return_ a response, which means that the `response` future
      // will _not_ fail, so in that case this test doesn't apply.
      XCTAssertThrowsError(try call.response.wait()) {
        XCTAssertEqual(expectedError, $0 as? GRPCStatus)
      }
    }
  }

  func testServerStreaming() throws {
    let call = client
      .expand(Echo_EchoRequest(text: "foo")) { XCTFail("no message expected, got \($0)") }
    // Nothing to throw here, but the `status` should be the expected error.
    XCTAssertEqual(self.expectedError, try call.status.wait())
    let trailers = try call.trailingMetadata.wait()
    if let expected = self.expectedMetadata {
      for (name, value, _) in expected {
        XCTAssertTrue(trailers[name].contains(value))
      }
    }
  }

  func testBidirectionalStreaming() throws {
    let call = client.update { XCTFail("no message expected, got \($0)") }
    // This is racing with the server error; it might fail, it might not.
    try? call.sendEnd().wait()
    // Nothing to throw here, but the `status` should be the expected error.
    XCTAssertEqual(self.expectedError, try call.status.wait())
    let trailers = try call.trailingMetadata.wait()
    if let expected = self.expectedMetadata {
      for (name, value, _) in expected {
        XCTAssertTrue(trailers[name].contains(value))
      }
    }
  }
}
