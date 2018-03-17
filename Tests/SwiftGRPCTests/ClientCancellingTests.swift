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

class ClientCancellingTests: BasicEchoTestCase {
  static var allTests: [(String, (ClientCancellingTests) -> () throws -> Void)] {
    return [
      ("testUnary", testUnary),
      ("testClientStreaming", testClientStreaming),
      ("testServerStreaming", testServerStreaming),
      ("testBidirectionalStreaming", testBidirectionalStreaming),
    ]
  }
}

extension ClientCancellingTests {
  func testUnary() {
    let completionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.get(Echo_EchoRequest(text: "foo bar baz")) { response, callResult in
      XCTAssertNil(response)
      XCTAssertEqual(.cancelled, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }
    
    call.cancel()
    
    waitForExpectations(timeout: defaultTimeout)
  }
  
  func testClientStreaming() {
    let completionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.collect { callResult in
      XCTAssertEqual(.cancelled, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }
    
    call.cancel()
    
    let sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in XCTAssertEqual(.unknown, $0 as! CallError); sendExpectation.fulfill() }
    call.waitForSendOperationsToFinish()
    
    do {
      let result = try call.closeAndReceive()
      XCTFail("should have thrown, received \(result) instead")
    } catch let receiveError {
      XCTAssertEqual(.unknown, (receiveError as! RPCError).callResult!.statusCode)
    }
    
    waitForExpectations(timeout: defaultTimeout)
  }
  
  func testServerStreaming() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.expand(Echo_EchoRequest(text: "foo bar baz")) { callResult in
      XCTAssertEqual(.cancelled, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }
    
    XCTAssertEqual("Swift echo expand (0): foo", try! call.receive()!.text)
    
    call.cancel()
    
    do {
      let result = try call.receive()
      XCTFail("should have thrown, received \(String(describing: result)) instead")
    } catch let receiveError {
      XCTAssertEqual(.unknown, (receiveError as! RPCError).callResult!.statusCode)
    }
    
    waitForExpectations(timeout: defaultTimeout)
  }
  
  func testBidirectionalStreaming() {
    let finalCompletionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.cancelled, callResult.statusCode)
      finalCompletionHandlerExpectation.fulfill()
    }
    
    var sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    XCTAssertEqual("Swift echo update (0): foo", try! call.receive()!.text)
    
    call.cancel()
    
    sendExpectation = expectation(description: "send completion handler 2 called")
    try! call.send(Echo_EchoRequest(text: "bar")) { [sendExpectation] in XCTAssertEqual(.unknown, $0 as! CallError); sendExpectation.fulfill() }
    do {
      let result = try call.receive()
      XCTFail("should have thrown, received \(String(describing: result)) instead")
    } catch let receiveError {
      XCTAssertEqual(.unknown, (receiveError as! RPCError).callResult!.statusCode)
    }
    
    let closeCompletionHandlerExpectation = expectation(description: "close completion handler called")
    try! call.closeSend { closeCompletionHandlerExpectation.fulfill() }
    
    waitForExpectations(timeout: defaultTimeout)
  }
}
