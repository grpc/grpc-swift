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
@testable import SwiftGRPC
import XCTest

// Sample test suite to demonstrate how one would test a `Provider` implementation.
// These tests don't really test the logic of the SwiftGRPC library, but are meant
// as an example of how one would go about testing their own client/server code that
// relies on SwiftGRPC.
class ServerTestExample: XCTestCase {
  static var allTests: [(String, (ServerTestExample) -> () throws -> Void)] {
    return [
      ("testUnary", testUnary),
      ("testClientStreaming", testClientStreaming),
      ("testServerStreaming", testServerStreaming),
      ("testBidirectionalStreaming", testBidirectionalStreaming)
    ]
  }
  
  var provider: Echo_EchoProvider!
  
  override func setUp() {
    super.setUp()
    
    provider = EchoProvider()
  }
  
  override func tearDown() {
    provider = nil
    
    super.tearDown()
  }
}

extension ServerTestExample {
  func testUnary() {
    XCTAssertEqual(Echo_EchoResponse(text: "Swift echo get: "),
                   try provider.get(request: Echo_EchoRequest(text: ""), session: Echo_EchoGetSessionTestStub()))
    XCTAssertEqual(Echo_EchoResponse(text: "Swift echo get: foo"),
                   try provider.get(request: Echo_EchoRequest(text: "foo"), session: Echo_EchoGetSessionTestStub()))
    XCTAssertEqual(Echo_EchoResponse(text: "Swift echo get: foo bar"),
                   try provider.get(request: Echo_EchoRequest(text: "foo bar"), session: Echo_EchoGetSessionTestStub()))
  }
  
  func testClientStreaming() {
    let session = Echo_EchoCollectSessionTestStub()
    session.inputs = ["foo", "bar", "baz"].map { Echo_EchoRequest(text: $0) }
    
    XCTAssertEqual(Echo_EchoResponse(text: "Swift echo collect: foo bar baz"), try provider.collect(session: session)!)
  }
  
  func testServerStreaming() {
    let session = Echo_EchoExpandSessionTestStub()
    XCTAssertEqual(.ok, try provider.expand(request: Echo_EchoRequest(text: "foo bar baz"), session: session)!.code)
    
    XCTAssertEqual(["foo", "bar", "baz"].enumerated()
      .map { Echo_EchoResponse(text: "Swift echo expand (\($0)): \($1)") },
                   session.outputs)
  }
  
  func testBidirectionalStreaming() {
    let inputStrings = ["foo", "bar", "baz"]
    let session = Echo_EchoUpdateSessionTestStub()
    session.inputs = inputStrings.map { Echo_EchoRequest(text: $0) }
    XCTAssertEqual(.ok, try! provider.update(session: session)!.code)
    
    XCTAssertEqual(inputStrings.enumerated()
      .map { Echo_EchoResponse(text: "Swift echo update (\($0)): \($1)") },
                   session.outputs)
  }
}
