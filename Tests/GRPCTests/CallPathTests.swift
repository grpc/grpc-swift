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

import XCTest

@testable import GRPC

class CallPathTests: GRPCTestCase {
  func testSplitPathNormal() {
    let path = "/server/method"
    let parsedPath = CallPath(requestURI: path)
    let splitPath = path.split(separator: "/")

    XCTAssertEqual(splitPath[0], String.SubSequence(parsedPath!.service))
    XCTAssertEqual(splitPath[1], String.SubSequence(parsedPath!.method))
  }

  func testSplitPathTooShort() {
    let path = "/badPath"
    let parsedPath = CallPath(requestURI: path)

    XCTAssertNil(parsedPath)
  }

  func testSplitPathTooLong() {
    let path = "/server/method/discard"
    let parsedPath = CallPath(requestURI: path)
    let splitPath = path.split(separator: "/")

    XCTAssertEqual(splitPath[0], String.SubSequence(parsedPath!.service))
    XCTAssertEqual(splitPath[1], String.SubSequence(parsedPath!.method))
  }

  func testTrimPrefixEmpty() {
    var toSplit = "".utf8[...]
    let head = toSplit.trimPrefix(to: UInt8(ascii: "/"))
    XCTAssertNil(head)
    XCTAssertEqual(toSplit.count, 0)
  }

  func testTrimPrefixAll() {
    let source = "words"
    var toSplit = source.utf8[...]
    let head = toSplit.trimPrefix(to: UInt8(ascii: "/"))
    XCTAssertEqual(head?.count, source.utf8.count)
    XCTAssertEqual(toSplit.count, 0)
  }

  func testTrimPrefixAndRest() {
    let source = "words/moreWords"
    var toSplit = source.utf8[...]
    let head = toSplit.trimPrefix(to: UInt8(ascii: "/"))
    XCTAssertEqual(head?.count, "words".utf8.count)
    XCTAssertEqual(toSplit.count, "moreWords".utf8.count)
  }
}
