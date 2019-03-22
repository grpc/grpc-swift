/*
 * Copyright 2019, gRPC Authors All rights reserved.
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

protocol NIOFunctionalTests: class {
  func testUnary() throws
  func testUnaryLotsOfRequests() throws
  func testUnaryWithLargeData() throws
  func testUnaryEmptyRequest() throws
  func testClientStreaming() throws
  func testClientStreamingLotsOfMessages() throws
  func testServerStreaming() throws
  func testServerStreamingLotsOfMessages() throws
  func testBidirectionalStreamingBatched() throws
  func testBidirectionalStreamingPingPong() throws
  func testBidirectionalStreamingLotsOfMessagesBatched() throws
  func testBidirectionalStreamingLotsOfMessagesPingPong() throws
}

extension NIOFunctionalTests {
  static var allTests: [(String, (Self) -> () throws -> Void)] {
    return [
      ("testUnary", testUnary),
      ("testUnaryLotsOfRequests", testUnaryLotsOfRequests),
      ("testUnaryWithLargeData", testUnaryWithLargeData),
      ("testUnaryEmptyRequest", testUnaryEmptyRequest),
      ("testClientStreaming", testClientStreaming),
      ("testClientStreamingLotsOfMessages", testClientStreamingLotsOfMessages),
      ("testServerStreaming", testServerStreaming),
      ("testServerStreamingLotsOfMessages", testServerStreamingLotsOfMessages),
      ("testBidirectionalStreamingBatched", testBidirectionalStreamingBatched),
      ("testBidirectionalStreamingPingPong", testBidirectionalStreamingPingPong),
      ("testBidirectionalStreamingLotsOfMessagesBatched", testBidirectionalStreamingLotsOfMessagesBatched),
      ("testBidirectionalStreamingLotsOfMessagesPingPong", testBidirectionalStreamingLotsOfMessagesPingPong)
    ]
  }
}

class NIOFunctionalTestsInsecureTransport: NIOEchoTestCaseBase, NIOFunctionalTests {
  override var transportSecurity: TransportSecurity {
    return .none
  }

  var aFewStrings: [String] {
    return ["foo", "bar", "baz"]
  }

  var lotsOfStrings: [String] {
    return (0..<5_000).map {
      String(describing: $0)
    }
  }
}

extension NIOFunctionalTestsInsecureTransport {
  func makeExpectation(description: String, expectedFulfillmentCount: Int = 1, assertForOverFulfill: Bool = true) -> XCTestExpectation {
    let expectation = self.expectation(description: description)
    expectation.expectedFulfillmentCount = expectedFulfillmentCount
    expectation.assertForOverFulfill = assertForOverFulfill
    return expectation
  }

  func makeStatusExpectation(expectedFulfillmentCount: Int = 1) -> XCTestExpectation {
    return makeExpectation(description: "Expecting status received",
                           expectedFulfillmentCount: expectedFulfillmentCount)
  }

  func makeResponseExpectation(expectedFulfillmentCount: Int = 1) -> XCTestExpectation {
    return makeExpectation(description: "Expecting \(expectedFulfillmentCount) response(s)",
                           expectedFulfillmentCount: expectedFulfillmentCount)
  }
}

extension NIOFunctionalTestsInsecureTransport {
  func doTestUnary(request: Echo_EchoRequest, expect response: Echo_EchoResponse, file: StaticString = #file, line: UInt = #line) {
    let responseExpectation = self.makeResponseExpectation()
    let statusExpectation = self.makeStatusExpectation()

    let call = client.get(request)
    call.response.assertEqual(response, fulfill: responseExpectation, file: file, line: line)
    call.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation, file: file, line: line)

    self.wait(for: [responseExpectation, statusExpectation], timeout: self.defaultTestTimeout)
  }

  func doTestUnary(message: String, file: StaticString = #file, line: UInt = #line) {
    self.doTestUnary(request: Echo_EchoRequest(text: message), expect: Echo_EchoResponse(text: "Swift echo get: \(message)"), file: file, line: line)
  }

  func testUnary() throws {
    self.doTestUnary(message: "foo")
  }

  func testUnaryLotsOfRequests() throws {
    self.defaultTestTimeout = 60.0

    // Sending that many requests at once can sometimes trip things up, it seems.
    let clockStart = clock()
    let numberOfRequests = 2_000
    let responseExpectation = self.makeResponseExpectation(expectedFulfillmentCount: numberOfRequests)
    let statusExpectation = self.makeStatusExpectation(expectedFulfillmentCount: numberOfRequests)

    for i in 0..<numberOfRequests {
      if i % 1_000 == 0 && i > 0 {
        print("\(i) requests sent so far, elapsed time: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
      }

      let request = Echo_EchoRequest(text: "foo \(i)")
      let response = Echo_EchoResponse(text: "Swift echo get: foo \(i)")

      let call = client.get(request)
      call.response.assertEqual(response, fulfill: responseExpectation)
      call.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation)
    }
    print("total time to send \(numberOfRequests) requests: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")

    self.wait(for: [responseExpectation, statusExpectation], timeout: self.defaultTestTimeout)
    print("total time to receive \(numberOfRequests) responses: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
  }

  func testUnaryWithLargeData() throws {
    // Default max frame size is: 16,384. We'll exceed this as we also have to send the size and compression flag.
    let longMessage = String(repeating: "e", count: 16_384)
    self.doTestUnary(message: longMessage)
  }

  func testUnaryEmptyRequest() throws {
    self.doTestUnary(request: Echo_EchoRequest(), expect: Echo_EchoResponse(text: "Swift echo get: "))
  }
}

extension NIOFunctionalTestsInsecureTransport {
  func doTestClientStreaming(messages: [String], file: StaticString = #file, line: UInt = #line) throws {
    let responseExpectation = self.makeResponseExpectation()
    let statusExpectation = self.makeStatusExpectation()

    let call = client.collect(callOptions: CallOptions(timeout: .infinite))
    call.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation, file: file, line: line)
    call.response.assertEqual(Echo_EchoResponse(text: "Swift echo collect: \(messages.joined(separator: " "))"), fulfill: responseExpectation)

    var queue = call.newMessageQueue()
    for message in messages {
      queue = queue.flatMap { call.sendMessage(Echo_EchoRequest(text: message)) }
    }
    queue.whenSuccess { call.sendEnd(promise: nil) }

    self.wait(for: [responseExpectation, statusExpectation], timeout: self.defaultTestTimeout)
  }

  func testClientStreaming() {
    XCTAssertNoThrow(try doTestClientStreaming(messages: aFewStrings))
  }

  func testClientStreamingLotsOfMessages() throws {
    self.defaultTestTimeout = 15.0
    XCTAssertNoThrow(try doTestClientStreaming(messages: lotsOfStrings))
  }
}

extension NIOFunctionalTestsInsecureTransport {
  func doTestServerStreaming(messages: [String], file: StaticString = #file, line: UInt = #line) throws {
    let responseExpectation = self.makeResponseExpectation(expectedFulfillmentCount: messages.count)
    let statusExpectation = self.makeStatusExpectation()

    var iterator = messages.enumerated().makeIterator()
    let call = client.expand(Echo_EchoRequest(text: messages.joined(separator: " "))) { response in
      if let (index, message) = iterator.next() {
        XCTAssertEqual(Echo_EchoResponse(text: "Swift echo expand (\(index)): \(message)"), response, file: file, line: line)
        responseExpectation.fulfill()
      } else {
        XCTFail("Too many responses received", file: file, line: line)
      }
    }

    call.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation, file: file, line: line)
    self.wait(for: [responseExpectation, statusExpectation], timeout: self.defaultTestTimeout)
  }

  func testServerStreaming() {
    XCTAssertNoThrow(try doTestServerStreaming(messages: aFewStrings))
  }

  func testServerStreamingLotsOfMessages() {
    self.defaultTestTimeout = 15.0
    XCTAssertNoThrow(try doTestServerStreaming(messages: lotsOfStrings))
  }
}

extension NIOFunctionalTestsInsecureTransport {
  private func doTestBidirectionalStreaming(messages: [String], waitForEachResponse: Bool = false, file: StaticString = #file, line: UInt = #line) throws {
    let responseExpectation = self.makeResponseExpectation(expectedFulfillmentCount: messages.count)
    let statusExpectation = self.makeStatusExpectation()

    let responseReceived = waitForEachResponse ? DispatchSemaphore(value: 0) : nil

    var iterator = messages.enumerated().makeIterator()
    let call = client.update { response in
      if let (index, message) = iterator.next() {
        XCTAssertEqual(Echo_EchoResponse(text: "Swift echo update (\(index)): \(message)"), response, file: file, line: line)
        responseExpectation.fulfill()
        responseReceived?.signal()
      } else {
        XCTFail("Too many responses received", file: file, line: line)
      }
    }

    call.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation, file: file, line: line)

    messages.forEach { part in
      call.sendMessage(Echo_EchoRequest(text: part), promise: nil)
      XCTAssertNotEqual(responseReceived?.wait(timeout: .now() + .seconds(1)), .some(.timedOut), file: file, line: line)
    }
    call.sendEnd(promise: nil)

    self.wait(for: [responseExpectation, statusExpectation], timeout: self.defaultTestTimeout)
  }

  func testBidirectionalStreamingBatched() throws {
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: aFewStrings))
  }

  func testBidirectionalStreamingPingPong() throws {
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: aFewStrings, waitForEachResponse: true))
  }

  func testBidirectionalStreamingLotsOfMessagesBatched() throws {
    self.defaultTestTimeout = 15.0
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: lotsOfStrings))
  }

  func testBidirectionalStreamingLotsOfMessagesPingPong() throws {
    self.defaultTestTimeout = 15.0
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: lotsOfStrings, waitForEachResponse: true))
  }
}

class NIOFunctionalTestsAnonymousClient: NIOFunctionalTestsInsecureTransport {
  override var transportSecurity: TransportSecurity {
    return .anonymousClient
  }
}

class NIOFunctionalTestsMutualAuthentication: NIOFunctionalTestsInsecureTransport {
  override var transportSecurity: TransportSecurity {
    return .mutualAuthentication
  }
}
