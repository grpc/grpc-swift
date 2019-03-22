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

class EchoTests: BasicEchoTestCase {
  static let lotsOfStrings = (0..<1000).map { String(describing: $0) }
}

class EchoTestsSecure: EchoTests {
  override var security: Security { return .ssl }
}

class EchoTestsMutualAuth: EchoTests {
  override var security: Security { return .tlsMutualAuth }
}

extension EchoTests {
  func testUnary() {
    XCTAssertEqual("Swift echo get: foo", try! client.get(Echo_EchoRequest(text: "foo")).text)
    XCTAssertEqual("Swift echo get: foo", try! client.get(Echo_EchoRequest(text: "foo")).text)
    XCTAssertEqual("Swift echo get: foo", try! client.get(Echo_EchoRequest(text: "foo")).text)
    XCTAssertEqual("Swift echo get: foo", try! client.get(Echo_EchoRequest(text: "foo")).text)
    XCTAssertEqual("Swift echo get: foo", try! client.get(Echo_EchoRequest(text: "foo")).text)
  }

  func testUnaryLotsOfRequests() {
    // No need to spam the log with 10k lines.
    server.shouldLogRequests = false
    // Sending that many requests at once can sometimes trip things up, it seems.
    client.timeout = 5.0
    let clockStart = clock()
    let numberOfRequests = 10_000
    for i in 0..<numberOfRequests {
      if i % 1_000 == 0 && i > 0 {
        print("\(i) requests sent so far, elapsed time: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
      }
      XCTAssertEqual("Swift echo get: foo \(i)", try client.get(Echo_EchoRequest(text: "foo \(i)")).text)
    }
    print("total time for \(numberOfRequests) requests: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
  }
}

extension EchoTests {
  func testClientStreaming() {
    let completionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.collect { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }

    var sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    sendExpectation = expectation(description: "send completion handler 2 called")
    try! call.send(Echo_EchoRequest(text: "bar")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    sendExpectation = expectation(description: "send completion handler 3 called")
    try! call.send(Echo_EchoRequest(text: "baz")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    call.waitForSendOperationsToFinish()

    let response = try! call.closeAndReceive()
    XCTAssertEqual("Swift echo collect: foo bar baz", response.text)

    waitForExpectations(timeout: defaultTimeout)
  }

  func testClientStreamingLotsOfMessages() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.collect { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }

    for string in EchoTests.lotsOfStrings {
      let sendExpectation = expectation(description: "send completion handler \(string) called")
      try! call.send(Echo_EchoRequest(text: string)) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    }
    call.waitForSendOperationsToFinish()

    let response = try! call.closeAndReceive()
    XCTAssertEqual("Swift echo collect: " + EchoTests.lotsOfStrings.joined(separator: " "), response.text)

    waitForExpectations(timeout: defaultTimeout)
  }
}

extension EchoTests {
  func testServerStreaming() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.expand(Echo_EchoRequest(text: "foo bar baz")) { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }

    XCTAssertEqual("Swift echo expand (0): foo", try! call.receive()!.text)
    XCTAssertEqual("Swift echo expand (1): bar", try! call.receive()!.text)
    XCTAssertEqual("Swift echo expand (2): baz", try! call.receive()!.text)
    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }

  func testServerStreamingLotsOfMessages() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    let call = try! client.expand(Echo_EchoRequest(text: EchoTests.lotsOfStrings.joined(separator: " "))) { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }

    for string in EchoTests.lotsOfStrings {
      XCTAssertEqual("Swift echo expand (\(string)): \(string)", try! call.receive()!.text)
    }
    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }
}

extension EchoTests {
  func testBidirectionalStreamingBatched() {
    let finalCompletionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      finalCompletionHandlerExpectation.fulfill()
    }

    var sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    sendExpectation = expectation(description: "send completion handler 2 called")
    try! call.send(Echo_EchoRequest(text: "bar")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    sendExpectation = expectation(description: "send completion handler 3 called")
    try! call.send(Echo_EchoRequest(text: "baz")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    call.waitForSendOperationsToFinish()

    let closeCompletionHandlerExpectation = expectation(description: "close completion handler called")
    try! call.closeSend { closeCompletionHandlerExpectation.fulfill() }

    XCTAssertEqual("Swift echo update (0): foo", try! call.receive()!.text)
    XCTAssertEqual("Swift echo update (1): bar", try! call.receive()!.text)
    XCTAssertEqual("Swift echo update (2): baz", try! call.receive()!.text)
    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }

  func testBidirectionalStreamingPingPong() {
    let finalCompletionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      finalCompletionHandlerExpectation.fulfill()
    }

    var sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    XCTAssertEqual("Swift echo update (0): foo", try! call.receive()!.text)

    sendExpectation = expectation(description: "send completion handler 2 called")
    try! call.send(Echo_EchoRequest(text: "bar")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    XCTAssertEqual("Swift echo update (1): bar", try! call.receive()!.text)

    sendExpectation = expectation(description: "send completion handler 3 called")
    try! call.send(Echo_EchoRequest(text: "baz")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    XCTAssertEqual("Swift echo update (2): baz", try! call.receive()!.text)

    let closeCompletionHandlerExpectation = expectation(description: "close completion handler called")
    try! call.closeSend { closeCompletionHandlerExpectation.fulfill() }

    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }

  func testBidirectionalStreamingLotsOfMessagesBatched() {
    let finalCompletionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      finalCompletionHandlerExpectation.fulfill()
    }

    for string in EchoTests.lotsOfStrings {
      let sendExpectation = expectation(description: "send completion handler \(string) called")
      try! call.send(Echo_EchoRequest(text: string)) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    }
    call.waitForSendOperationsToFinish()

    let closeCompletionHandlerExpectation = expectation(description: "close completion handler called")
    try! call.closeSend { closeCompletionHandlerExpectation.fulfill() }

    for string in EchoTests.lotsOfStrings {
      XCTAssertEqual("Swift echo update (\(string)): \(string)", try! call.receive()!.text)
    }
    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }

  func testBidirectionalStreamingLotsOfMessagesPingPong() {
    let finalCompletionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      finalCompletionHandlerExpectation.fulfill()
    }

    for string in EchoTests.lotsOfStrings {
      let sendExpectation = expectation(description: "send completion handler \(string) called")
      try! call.send(Echo_EchoRequest(text: string)) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
      XCTAssertEqual("Swift echo update (\(string)): \(string)", try! call.receive()!.text)
    }

    let closeCompletionHandlerExpectation = expectation(description: "close completion handler called")
    try! call.closeSend { closeCompletionHandlerExpectation.fulfill() }

    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }
}
