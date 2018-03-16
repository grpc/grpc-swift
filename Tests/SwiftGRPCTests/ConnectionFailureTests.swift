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

// TODO(danielalm): Also test connection failure with regards to SSL issues.
class ConnectionFailureTests: XCTestCase {
  static var allTests: [(String, (ConnectionFailureTests) -> () throws -> Void)] {
    return [
      ("testConnectionFailureUnary", testConnectionFailureUnary),
      ("testConnectionFailureClientStreaming", testConnectionFailureClientStreaming),
      ("testConnectionFailureServerStreaming", testConnectionFailureServerStreaming),
      ("testConnectionFailureBidirectionalStreaming", testConnectionFailureBidirectionalStreaming)
    ]
  }
  
  let address = "localhost:5050"
  
  let defaultTimeout: TimeInterval = 0.5
}

extension ConnectionFailureTests {
  func testConnectionFailureUnary() {
    let client = Echo_EchoServiceClient(address: "localhost:1234", secure: false)
    client.timeout = defaultTimeout
    
    do {
      _ = try client.get(Echo_EchoRequest(text: "foo")).text
      XCTFail("should have thrown")
    } catch {
      guard case let .callError(callResult) = error as! RPCError
        else { XCTFail("unexpected error \(error)"); return }
      XCTAssertEqual(.unavailable, callResult.statusCode)
      XCTAssertEqual("Connect Failed", callResult.statusMessage)
    }
  }
  
  func testConnectionFailureClientStreaming() {
    let client = Echo_EchoServiceClient(address: "localhost:1234", secure: false)
    client.timeout = defaultTimeout
    
    let completionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.collect { callResult in
      XCTAssertEqual(.unavailable, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }
    
    let sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in
      XCTAssertEqual(.unknown, $0 as! CallError)
      sendExpectation.fulfill()
    }
    call.waitForSendOperationsToFinish()
    
    do {
      _ = try call.closeAndReceive()
      XCTFail("should have thrown")
    } catch let receiveError {
      XCTAssertEqual(.unknown, (receiveError as! RPCError).callResult!.statusCode)
    }
    
    waitForExpectations(timeout: defaultTimeout)
  }
  
  func testConnectionFailureServerStreaming() {
    let client = Echo_EchoServiceClient(address: "localhost:1234", secure: false)
    client.timeout = defaultTimeout
    
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.expand(Echo_EchoRequest(text: "foo bar baz")) { callResult in
      XCTAssertEqual(.unavailable, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }
    
    do {
      _ = try call.receive()
      XCTFail("should have thrown")
    } catch let receiveError {
      XCTAssertEqual(.unknown, (receiveError as! RPCError).callResult!.statusCode)
    }
    
    waitForExpectations(timeout: defaultTimeout)
  }
  
  func testConnectionFailureBidirectionalStreaming() {
    let client = Echo_EchoServiceClient(address: "localhost:1234", secure: false)
    client.timeout = defaultTimeout
    
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.unavailable, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }
    
    let sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in
      XCTAssertEqual(.unknown, $0 as! CallError)
      sendExpectation.fulfill()
    }
    call.waitForSendOperationsToFinish()
    
    do {
      _ = try call.receive()
      XCTFail("should have thrown")
    } catch let receiveError {
      XCTAssertEqual(.unknown, (receiveError as! RPCError).callResult!.statusCode)
    }
    
    waitForExpectations(timeout: defaultTimeout)
  }
}
