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
@testable import gRPC
import XCTest

extension Echo_EchoRequest {
  init(text: String) {
    self.text = text
  }
}

class EchoTests: XCTestCase {
  static var allTests: [(String, (EchoTests) -> () throws -> Void)] {
    return [
      ("testUnary", testUnary),
      ("testClientStreaming", testClientStreaming),
      ("testClientStreamingLotsOfMessages", testClientStreamingLotsOfMessages),
      ("testServerStreaming", testServerStreaming),
      ("testServerStreamingLotsOfMessages", testServerStreamingLotsOfMessages),
      ("testBidirectionalStreamingBatched", testBidirectionalStreamingBatched),
      ("testBidirectionalStreamingPingPong", testBidirectionalStreamingPingPong)
    ]
  }
  
  static let lotsOfStrings = (0..<1000).map { String(describing: $0) }
  
	let provider = EchoProvider()
	var server: Echo_EchoServer!
  var client: Echo_EchoServiceClient!
  
  var secure: Bool { return false }
	
	override func setUp() {
    super.setUp()
    
    let address = "localhost:5050"
    if secure {
      let certificateString = String(data: certificateForTests, encoding: .utf8)!
      server = Echo_EchoServer(address: address,
                               certificateString: certificateString,
                               keyString: String(data: keyForTests, encoding: .utf8)!,
                               provider: provider)
      server.start(queue: DispatchQueue.global())
      client = Echo_EchoServiceClient(address: address, certificates: certificateString, host: "example.com")
    } else {
      server = Echo_EchoServer(address: address, provider: provider)
      server.start(queue: DispatchQueue.global())
      client = Echo_EchoServiceClient(address: address, secure: false)
    }
    
    client.timeout = 0.1
	}
  
  override func tearDown() {
    server = nil
    
    super.tearDown()
  }
}

// Currently broken and thus commented out.
// TODO(danielalm): Fix these.
//class EchoTestsSecure: EchoTests {
//  override var secure: Bool { return true }
//}

extension EchoTests {
  func testUnary() {
    let response = try! client.get(Echo_EchoRequest(text: "foo"))
    XCTAssertEqual("Swift echo get: foo", response.text)
  }
}

extension EchoTests {
  func testClientStreaming() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.collect { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }
    
    try! call.send(Echo_EchoRequest(text: "foo")) { XCTFail($0.localizedDescription) }
    try! call.send(Echo_EchoRequest(text: "bar")) { XCTFail($0.localizedDescription) }
    try! call.send(Echo_EchoRequest(text: "baz")) { XCTFail($0.localizedDescription) }
    call.waitForSendOperationsToFinish()
    
    let response = try! call.closeAndReceive()
    XCTAssertEqual("Swift echo collect: foo bar baz", response.text)
    
    wait(for: [completionHandlerExpectation], timeout: 0.1, enforceOrder: true)
  }
  
  func testClientStreamingLotsOfMessages() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.collect { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }
    
    for string in EchoTests.lotsOfStrings {
      try! call.send(Echo_EchoRequest(text: string)) { XCTFail($0.localizedDescription) }
    }
    call.waitForSendOperationsToFinish()
    
    let response = try! call.closeAndReceive()
    XCTAssertEqual("Swift echo collect: " + EchoTests.lotsOfStrings.joined(separator: " "), response.text)
    
    wait(for: [completionHandlerExpectation], timeout: 0.1, enforceOrder: true)
  }
}

extension EchoTests {
  func testServerStreaming() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.expand(Echo_EchoRequest(text: "foo bar baz")) { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }
    
    XCTAssertEqual("Swift echo expand (0): foo", try! call.receive().text)
    XCTAssertEqual("Swift echo expand (1): bar", try! call.receive().text)
    XCTAssertEqual("Swift echo expand (2): baz", try! call.receive().text)
    
    wait(for: [completionHandlerExpectation], timeout: 0.1, enforceOrder: true)
  }
  
  func testServerStreamingLotsOfMessages() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.expand(Echo_EchoRequest(text: EchoTests.lotsOfStrings.joined(separator: " "))) { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }
    
    for string in EchoTests.lotsOfStrings {
      XCTAssertEqual("Swift echo expand (\(string)): \(string)", try! call.receive().text)
    }
    
    wait(for: [completionHandlerExpectation], timeout: 0.1, enforceOrder: true)
  }
}

extension EchoTests {
  func testBidirectionalStreamingBatched() {
    let finalCompletionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      finalCompletionHandlerExpectation.fulfill()
    }
    
    try! call.send(Echo_EchoRequest(text: "foo")) { XCTFail($0.localizedDescription) }
    try! call.send(Echo_EchoRequest(text: "bar")) { XCTFail($0.localizedDescription) }
    try! call.send(Echo_EchoRequest(text: "baz")) { XCTFail($0.localizedDescription) }
    call.waitForSendOperationsToFinish()
    
    let closeCompletionHandlerExpectation = expectation(description: "close completion handler called")
    try! call.closeSend { closeCompletionHandlerExpectation.fulfill() }
    
    XCTAssertEqual("Swift echo update (0): foo", try! call.receive().text)
    XCTAssertEqual("Swift echo update (1): bar", try! call.receive().text)
    XCTAssertEqual("Swift echo update (2): baz", try! call.receive().text)
    
    wait(for: [closeCompletionHandlerExpectation, finalCompletionHandlerExpectation],
         timeout: 0.1, enforceOrder: true)
  }
  
  func testBidirectionalStreamingPingPong() {
    let finalCompletionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      finalCompletionHandlerExpectation.fulfill()
    }
    
    try! call.send(Echo_EchoRequest(text: "foo")) { XCTFail($0.localizedDescription) }
    XCTAssertEqual("Swift echo update (0): foo", try! call.receive().text)
    try! call.send(Echo_EchoRequest(text: "bar")) { XCTFail($0.localizedDescription) }
    XCTAssertEqual("Swift echo update (1): bar", try! call.receive().text)
    try! call.send(Echo_EchoRequest(text: "baz")) { XCTFail($0.localizedDescription) }
    XCTAssertEqual("Swift echo update (2): baz", try! call.receive().text)
    
    let closeCompletionHandlerExpectation = expectation(description: "close completion handler called")
    try! call.closeSend { closeCompletionHandlerExpectation.fulfill() }
    
    wait(for: [closeCompletionHandlerExpectation, finalCompletionHandlerExpectation],
         timeout: 0.1, enforceOrder: true)
  }
}
