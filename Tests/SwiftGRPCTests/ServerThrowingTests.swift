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

fileprivate let testStatus = ServerStatus(code: .permissionDenied, message: "custom status message")

fileprivate class StatusThrowingProvider: Echo_EchoProvider {
  func get(request: Echo_EchoRequest, session _: Echo_EchoGetSession) throws -> Echo_EchoResponse {
    throw testStatus
  }
  
  func expand(request: Echo_EchoRequest, session: Echo_EchoExpandSession) throws {
    throw testStatus
  }
  
  func collect(session: Echo_EchoCollectSession) throws {
    throw testStatus
  }
  
  func update(session: Echo_EchoUpdateSession) throws {
    throw testStatus
  }
}

class ServerThrowingTests: BasicEchoTestCase {
  static var allTests: [(String, (ServerThrowingTests) -> () throws -> Void)] {
    return [
      ("testServerThrowsUnary", testServerThrowsUnary),
      ("testServerThrowsClientStreaming", testServerThrowsClientStreaming),
      ("testServerThrowsServerStreaming", testServerThrowsServerStreaming),
      ("testServerThrowsBidirectionalStreaming", testServerThrowsBidirectionalStreaming)
    ]
  }
  
  override func makeProvider() -> Echo_EchoProvider { return StatusThrowingProvider() }
}

extension ServerThrowingTests {
  func testServerThrowsUnary() {
    do {
      _ = try client.get(Echo_EchoRequest(text: "foo")).text
      XCTFail("should have thrown")
    } catch {
      guard case let .callError(callResult) = error as! RPCError
        else { XCTFail("unexpected error \(error)"); return }
      XCTAssertEqual(.permissionDenied, callResult.statusCode)
      XCTAssertEqual("custom status message", callResult.statusMessage)
    }
  }
  
  func testServerThrowsClientStreaming() {
    let completionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.collect { callResult in
      XCTAssertEqual(.permissionDenied, callResult.statusCode)
      XCTAssertEqual("custom status message", callResult.statusMessage)
      completionHandlerExpectation.fulfill()
    }
    
    let sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in
      // The server only times out later in its lifecycle, so we shouldn't get an error when trying to send a message.
      XCTAssertNil($0)
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
  
  func testServerThrowsServerStreaming() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.expand(Echo_EchoRequest(text: "foo bar baz")) { callResult in
      XCTAssertEqual(.permissionDenied, callResult.statusCode)
      XCTAssertEqual("custom status message", callResult.statusMessage)
      completionHandlerExpectation.fulfill()
    }
    
    // TODO(danielalm): Why doesn't `call.receive()` throw once the call times out?
    XCTAssertNil(try! call.receive())
    
    waitForExpectations(timeout: defaultTimeout)
  }
  
  func testServerThrowsBidirectionalStreaming() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.permissionDenied, callResult.statusCode)
      XCTAssertEqual("custom status message", callResult.statusMessage)
      completionHandlerExpectation.fulfill()
    }
    
    let sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in
      // The server only times out later in its lifecycle, so we shouldn't get an error when trying to send a message.
      XCTAssertNil($0)
      sendExpectation.fulfill()
    }
    call.waitForSendOperationsToFinish()
    
    // FIXME(danielalm): Why does `call.receive()` only throw on Linux (but not macOS) once the call times out?
    #if os(Linux)
    do {
      _ = try call.receive()
      XCTFail("should have thrown")
    } catch let receiveError {
      XCTAssertEqual(.unknown, (receiveError as! RPCError).callResult!.statusCode)
    }
    #else
    XCTAssertNil(try! call.receive())
    #endif
    
    waitForExpectations(timeout: defaultTimeout)
  }
}
