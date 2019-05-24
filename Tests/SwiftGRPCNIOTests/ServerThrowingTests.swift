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
import Foundation
import NIO
import NIOHTTP1
import NIOHTTP2
@testable import SwiftGRPCNIO
import XCTest

let thrownError = GRPCStatus(code: .internalError, message: "expected error")
let transformedError = GRPCStatus(code: .aborted, message: "transformed error")

func assertEqualStatusIgnoringTrailers(_ status: GRPCStatus, _ otherStatus: GRPCStatus?) {
  guard let otherStatus = otherStatus else {
    XCTFail("status was nil")
    return
  }

  XCTAssertEqual(status.code, otherStatus.code)
  XCTAssertEqual(status.message, otherStatus.message)
}

// Motivation for two different providers: Throwing immediately causes the event observer future (in the
// client-streaming and bidi-streaming cases) to throw immediately, _before_ the corresponding handler has even added
// to the channel. We want to test that case as well as the one where we throw only _after_ the handler has been added
// to the channel.
class ImmediateThrowingEchoProviderNIO: Echo_EchoProvider {
  func get(request: Echo_EchoRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Echo_EchoResponse> {
    return context.eventLoop.makeFailedFuture(thrownError)
  }

  func expand(request: Echo_EchoRequest, context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<GRPCStatus> {
    return context.eventLoop.makeFailedFuture(thrownError)
  }

  func collect(context: UnaryResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeFailedFuture(thrownError)
  }

  func update(context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeFailedFuture(thrownError)
  }
}

extension EventLoop {
  func makeFailedFuture<T>(_ error: Error, delay: TimeInterval) -> EventLoopFuture<T> {
    return self.scheduleTask(in: .nanoseconds(TimeAmount.Value(delay * 1000 * 1000 * 1000))) { () }.futureResult
      .flatMapThrowing { _ -> T in throw error }
  }
}

/// See `ImmediateThrowingEchoProviderNIO`.
class DelayedThrowingEchoProviderNIO: Echo_EchoProvider {
  func get(request: Echo_EchoRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Echo_EchoResponse> {
    return context.eventLoop.makeFailedFuture(thrownError, delay: 0.01)
  }

  func expand(request: Echo_EchoRequest, context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<GRPCStatus> {
    return context.eventLoop.makeFailedFuture(thrownError, delay: 0.01)
  }

  func collect(context: UnaryResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeFailedFuture(thrownError, delay: 0.01)
  }

  func update(context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeFailedFuture(thrownError, delay: 0.01)
  }
}

/// Ensures that fulfilling the status promise (where possible) with an error yields the same result as failing the future.
class ErrorReturningEchoProviderNIO: ImmediateThrowingEchoProviderNIO {
  // There's no status promise to fulfill for unary calls (only the response promise), so that case is omitted.

  override func expand(request: Echo_EchoRequest, context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<GRPCStatus> {
    return context.eventLoop.makeSucceededFuture(thrownError)
  }

  override func collect(context: UnaryResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeSucceededFuture({ _ in
      context.responseStatus = thrownError
      context.responsePromise.succeed(Echo_EchoResponse())
    })
  }

  override func update(context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeSucceededFuture({ _ in
      context.statusPromise.succeed(thrownError)
    })
  }
}

private class ErrorTransformingDelegate: ServerErrorDelegate {
  func transformRequestHandlerError(_ error: Error, request: HTTPRequestHead) -> GRPCStatus? { return transformedError }
}

class ServerThrowingTests: NIOEchoTestCaseBase {
  var expectedError: GRPCStatus { return thrownError }

  override func makeEchoProvider() -> Echo_EchoProvider { return ImmediateThrowingEchoProviderNIO() }
}

class ServerDelayedThrowingTests: ServerThrowingTests {
  override func makeEchoProvider() -> Echo_EchoProvider { return DelayedThrowingEchoProviderNIO() }
}

class ClientThrowingWhenServerReturningErrorTests: ServerThrowingTests {
  override func makeEchoProvider() -> Echo_EchoProvider { return ErrorReturningEchoProviderNIO() }
}

class ServerErrorTransformingTests: ServerThrowingTests {
  override var expectedError: GRPCStatus { return transformedError }

  override func makeErrorDelegate() -> ServerErrorDelegate? { return ErrorTransformingDelegate() }
}

extension ServerThrowingTests {
  func testUnary() throws {
    let call = client.get(Echo_EchoRequest(text: "foo"))
    assertEqualStatusIgnoringTrailers(expectedError, try call.status.wait())
    XCTAssertThrowsError(try call.response.wait()) {
      assertEqualStatusIgnoringTrailers(expectedError, $0 as? GRPCStatus)
    }
  }

  func testClientStreaming() throws {
    let call = client.collect()
    XCTAssertNoThrow(try call.sendEnd().wait())
    assertEqualStatusIgnoringTrailers(expectedError, try call.status.wait())

    if type(of: makeEchoProvider()) != ErrorReturningEchoProviderNIO.self {
      // With `ErrorReturningEchoProviderNIO` we actually _return_ a response, which means that the `response` future
      // will _not_ fail, so in that case this test doesn't apply.
      XCTAssertThrowsError(try call.response.wait()) {
        assertEqualStatusIgnoringTrailers(expectedError, $0 as? GRPCStatus)
      }
    }
  }

  func testServerStreaming() throws {
    let call = client.expand(Echo_EchoRequest(text: "foo")) { XCTFail("no message expected, got \($0)") }
    // Nothing to throw here, but the `status` should be the expected error.
    assertEqualStatusIgnoringTrailers(expectedError, try call.status.wait())
  }

  func testBidirectionalStreaming() throws {
    let call = client.update() { XCTFail("no message expected, got \($0)") }
    XCTAssertNoThrow(try call.sendEnd().wait())
    // Nothing to throw here, but the `status` should be the expected error.
    assertEqualStatusIgnoringTrailers(expectedError, try call.status.wait())
  }
}
