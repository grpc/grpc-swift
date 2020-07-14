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
@testable import GRPC
import EchoModel
import XCTest

class FunctionalTestsInsecureTransport: EchoTestCaseBase {
  override var transportSecurity: TransportSecurity {
    return .none
  }

  var aFewStrings: [String] {
    return ["foo", "bar", "baz"]
  }

  var lotsOfStrings: [String] {
    return (0..<500).map {
      String(describing: $0)
    }
  }

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
    guard self.runTimeSensitiveTests() else { return }

    // Sending that many requests at once can sometimes trip things up, it seems.
    let clockStart = clock()
    let numberOfRequests = 200

    // Due to https://github.com/apple/swift-nio-http2/issues/87#issuecomment-483542401 we need to
    // limit the number of active streams. The default in NIOHTTP2 is 100, so we'll use it too.
    //
    // In the future we might want to build in some kind of mechanism which handles this for the
    // user.
    let batchSize = 100

    // Instead of setting a timeout out on the test we'll set one for each batch, if any of them
    // timeout then we'll bail out of the test.
    let batchTimeout: TimeInterval = 30.0
    self.continueAfterFailure = false

    for lowerBound in stride(from: 0, to: numberOfRequests, by: batchSize) {
      let upperBound = min(lowerBound + batchSize, numberOfRequests)
      let numberOfCalls = upperBound - lowerBound
      let responseExpectation = self.makeResponseExpectation(expectedFulfillmentCount: numberOfCalls)
      let statusExpectation = self.makeStatusExpectation(expectedFulfillmentCount: numberOfCalls)

      for i in lowerBound..<upperBound {
        let request = Echo_EchoRequest(text: "foo \(i)")
        let response = Echo_EchoResponse(text: "Swift echo get: foo \(i)")

        let get = client.get(request)
        get.response.assertEqual(response, fulfill: responseExpectation)
        get.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation)
      }

      if upperBound % 100 == 0 {
        print("\(upperBound) requests sent so far, elapsed time: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
      }

      self.wait(for: [responseExpectation, statusExpectation], timeout: batchTimeout)
    }

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

  func doTestClientStreaming(messages: [String], file: StaticString = #file, line: UInt = #line) throws {
    let responseExpectation = self.makeResponseExpectation()
    let statusExpectation = self.makeStatusExpectation()

    let call = client.collect(callOptions: CallOptions(timeLimit: .none))
    call.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation, file: file, line: line)
    call.response.assertEqual(Echo_EchoResponse(text: "Swift echo collect: \(messages.joined(separator: " "))"), fulfill: responseExpectation)

    call.sendMessages(messages.map { .init(text: $0) }, promise: nil)
    call.sendEnd(promise: nil)

    self.wait(for: [responseExpectation, statusExpectation], timeout: self.defaultTestTimeout)
  }

  func testClientStreaming() {
    XCTAssertNoThrow(try doTestClientStreaming(messages: aFewStrings))
  }

  func testClientStreamingLotsOfMessages() throws {
    guard self.runTimeSensitiveTests() else { return }
    XCTAssertNoThrow(try doTestClientStreaming(messages: lotsOfStrings))
  }

  private func doTestServerStreaming(messages: [String], line: UInt = #line) throws {
    let responseExpectation = self.makeResponseExpectation(expectedFulfillmentCount: messages.count)
    let statusExpectation = self.makeStatusExpectation()

    var iterator = messages.enumerated().makeIterator()
    let call = client.expand(Echo_EchoRequest(text: messages.joined(separator: " "))) { response in
      if let (index, message) = iterator.next() {
        XCTAssertEqual(Echo_EchoResponse(text: "Swift echo expand (\(index)): \(message)"), response, line: line)
        responseExpectation.fulfill()
      } else {
        XCTFail("Too many responses received", line: line)
      }
    }

    call.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation, line: line)
    self.wait(for: [responseExpectation, statusExpectation], timeout: self.defaultTestTimeout)
  }

  func testServerStreaming() {
    XCTAssertNoThrow(try doTestServerStreaming(messages: aFewStrings))
  }

  func testServerStreamingLotsOfMessages() {
    guard self.runTimeSensitiveTests() else { return }
    XCTAssertNoThrow(try doTestServerStreaming(messages: lotsOfStrings))
  }

  private func doTestBidirectionalStreaming(messages: [String], waitForEachResponse: Bool = false, line: UInt = #line) throws {
    let responseExpectation = self.makeResponseExpectation(expectedFulfillmentCount: messages.count)
    let statusExpectation = self.makeStatusExpectation()

    let responseReceived = waitForEachResponse ? DispatchSemaphore(value: 0) : nil

    var iterator = messages.enumerated().makeIterator()
    let call = client.update { response in
      if let (index, message) = iterator.next() {
        XCTAssertEqual(Echo_EchoResponse(text: "Swift echo update (\(index)): \(message)"), response, line: line)
        responseExpectation.fulfill()
        responseReceived?.signal()
      } else {
        XCTFail("Too many responses received", line: line)
      }
    }

    call.status.map { $0.code }.assertEqual(.ok, fulfill: statusExpectation, line: line)

    messages.forEach { part in
      call.sendMessage(Echo_EchoRequest(text: part), promise: nil)
      XCTAssertNotEqual(responseReceived?.wait(timeout: .now() + .seconds(30)), .some(.timedOut), line: line)
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
    guard self.runTimeSensitiveTests() else { return }
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: lotsOfStrings))
  }

  func testBidirectionalStreamingLotsOfMessagesPingPong() throws {
    guard self.runTimeSensitiveTests() else { return }
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: lotsOfStrings, waitForEachResponse: true))
  }
}

class FunctionalTestsAnonymousClient: FunctionalTestsInsecureTransport {
  override var transportSecurity: TransportSecurity {
    return .anonymousClient
  }
}

class FunctionalTestsMutualAuthentication: FunctionalTestsInsecureTransport {
  override var transportSecurity: TransportSecurity {
    return .mutualAuthentication
  }
}

// MARK: - Variants using NIO TS and Network.framework

// Unfortunately `swift test --generate-linuxmain` uses the macOS test discovery. Because of this
// it's difficult to avoid tests which run on Linux. To get around this shortcoming we can just
// run no-op tests on Linux.
@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
class FunctionalTestsInsecureTransportNIOTS: FunctionalTestsInsecureTransport {
  override var networkPreference: NetworkPreference {
    #if canImport(Network)
    return .userDefined(.networkFramework)
    #else
    // We shouldn't need this, since the tests won't do anything. However, we still need to be able
    // to compile this class.
    return .userDefined(.posix)
    #endif
  }

  override func testBidirectionalStreamingBatched() throws {
    #if canImport(Network)
    try super.testBidirectionalStreamingBatched()
    #endif
  }

  override func testBidirectionalStreamingLotsOfMessagesBatched() throws {
    #if canImport(Network)
    try super.testBidirectionalStreamingLotsOfMessagesBatched()
    #endif
  }

  override func testBidirectionalStreamingLotsOfMessagesPingPong() throws {
    #if canImport(Network)
    try super.testBidirectionalStreamingLotsOfMessagesPingPong()
    #endif
  }

  override func testBidirectionalStreamingPingPong() throws {
    #if canImport(Network)
    try super.testBidirectionalStreamingPingPong()
    #endif
  }

  override func testClientStreaming() {
    #if canImport(Network)
    super.testClientStreaming()
    #endif
  }

  override func testClientStreamingLotsOfMessages() throws {
    #if canImport(Network)
    try super.testClientStreamingLotsOfMessages()
    #endif
  }

  override func testServerStreaming() {
    #if canImport(Network)
    super.testServerStreaming()
    #endif
  }

  override func testServerStreamingLotsOfMessages() {
    #if canImport(Network)
    super.testServerStreamingLotsOfMessages()
    #endif
  }

  override func testUnary() throws {
    #if canImport(Network)
    try super.testUnary()
    #endif
  }

  override func testUnaryEmptyRequest() throws {
    #if canImport(Network)
    try super.testUnaryEmptyRequest()
    #endif
  }

  override func testUnaryLotsOfRequests() throws {
    #if canImport(Network)
    try super.testUnaryLotsOfRequests()
    #endif
  }

  override func testUnaryWithLargeData() throws {
    #if canImport(Network)
    try super.testUnaryWithLargeData()
    #endif
  }

}

@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
class FunctionalTestsAnonymousClientNIOTS: FunctionalTestsInsecureTransportNIOTS {
  override var transportSecurity: TransportSecurity {
    return .anonymousClient
  }
}

@available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
class FunctionalTestsMutualAuthenticationNIOTS: FunctionalTestsInsecureTransportNIOTS {
  override var transportSecurity: TransportSecurity {
    return .mutualAuthentication
  }
}
