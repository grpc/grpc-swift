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
import NIO
import XCTest

class LazyEventLoopPromiseTests: GRPCTestCase {
  func testGetFutureAfterSuccess() {
    let loop = EmbeddedEventLoop()
    var promise = loop.makeLazyPromise(of: String.self)
    promise.succeed("foo")
    XCTAssertEqual(try promise.getFutureResult().wait(), "foo")
  }

  func testGetFutureBeforeSuccess() {
    let loop = EmbeddedEventLoop()
    var promise = loop.makeLazyPromise(of: String.self)
    let future = promise.getFutureResult()
    promise.succeed("foo")
    XCTAssertEqual(try future.wait(), "foo")
  }

  func testGetFutureAfterError() {
    let loop = EmbeddedEventLoop()
    var promise = loop.makeLazyPromise(of: String.self)
    promise.fail(GRPCStatus.processingError)
    XCTAssertThrowsError(try promise.getFutureResult().wait()) { error in
      XCTAssertTrue(error is GRPCStatus)
    }
  }

  func testGetFutureBeforeError() {
    let loop = EmbeddedEventLoop()
    var promise = loop.makeLazyPromise(of: String.self)
    let future = promise.getFutureResult()
    promise.fail(GRPCStatus.processingError)
    XCTAssertThrowsError(try future.wait()) { error in
      XCTAssertTrue(error is GRPCStatus)
    }
  }

  func testGetFutureMultipleTimes() {
    let loop = EmbeddedEventLoop()
    var promise = loop.makeLazyPromise(of: String.self)
    let f1 = promise.getFutureResult()
    let f2 = promise.getFutureResult()
    promise.succeed("foo")
    XCTAssertEqual(try f1.wait(), try f2.wait())
  }

  func testMultipleResolutionsIgnored() {
    let loop = EmbeddedEventLoop()
    var promise = loop.makeLazyPromise(of: String.self)

    promise.succeed("foo")
    XCTAssertEqual(try promise.getFutureResult().wait(), "foo")

    promise.succeed("bar")
    XCTAssertEqual(try promise.getFutureResult().wait(), "foo")

    promise.fail(GRPCStatus.processingError)
    XCTAssertEqual(try promise.getFutureResult().wait(), "foo")
  }

  func testNoFuture() {
    let loop = EmbeddedEventLoop()
    var promise = loop.makeLazyPromise(of: String.self)
    promise.succeed("foo")
  }
}
