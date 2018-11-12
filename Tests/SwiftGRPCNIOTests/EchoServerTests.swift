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
import NIO
import NIOHTTP1
import NIOHTTP2
@testable import SwiftGRPC
@testable import SwiftGRPCNIO
import XCTest

// This class is what the SwiftGRPC user would actually implement to provide their service.
final class EchoGRPCProvider: Echo_EchoProvider_NIO {
  func get(request: Echo_EchoRequest, handler: UnaryCallHandler<Echo_EchoRequest, Echo_EchoResponse>) {
    var response = Echo_EchoResponse()
    response.text = "Swift echo get: " + request.text
    handler.responsePromise.succeed(result: response)
  }

  func collect(handler: ClientStreamingCallHandler<Echo_EchoRequest, Echo_EchoResponse>) -> (StreamEvent<Echo_EchoRequest>) -> Void {
    var parts: [String] = []
    return { event in
      switch event {
      case .message(let message):
        parts.append(message.text)

      case .end:
        var response = Echo_EchoResponse()
        response.text = "Swift echo collect: " + parts.joined(separator: " ")
        handler.responsePromise.succeed(result: response)
      }
    }
  }

  func expand(request: Echo_EchoRequest, handler: ServerStreamingCallHandler<Echo_EchoRequest, Echo_EchoResponse>) {
    let parts = request.text.components(separatedBy: " ")
    for (i, part) in parts.enumerated() {
      var response = Echo_EchoResponse()
      response.text = "Swift echo expand (\(i)): \(part)"
      _ = handler.sendMessage(response)
    }
    handler.sendStatus(.ok)
  }

  func update(handler: BidirectionalStreamingCallHandler<Echo_EchoRequest, Echo_EchoResponse>) -> (StreamEvent<Echo_EchoRequest>) -> Void {
    var count = 0
    return { event in
      switch event {
      case .message(let message):
        var response = Echo_EchoResponse()
        response.text = "Swift echo update (\(count)): \(message.text)"
        _ = handler.sendMessage(response)
        count += 1

      case .end:
        handler.sendStatus(.ok)
      }
    }
  }
}

class EchoServerTests: BasicEchoTestCase {
  static var allTests: [(String, (EchoServerTests) -> () throws -> Void)] {
    return [
      ("testUnary", testUnary),
      ("testUnaryLotsOfRequests", testUnaryLotsOfRequests),
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

  static let lotsOfStrings = (0..<1000).map { String(describing: $0) }

  var eventLoopGroup: MultiThreadedEventLoopGroup!
  var server: GRPCServer!

  override func setUp() {
    super.setUp()

    // This is how a GRPC server would actually be set up.
    eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    server = try! GRPCServer.start(
      hostname: "localhost", port: 5050, eventLoopGroup: eventLoopGroup, serviceProviders: [EchoGRPCProvider()])
      .wait()
  }

  override func tearDown() {
    try! server.close().wait()

    try! eventLoopGroup.syncShutdownGracefully()
    eventLoopGroup = nil

    super.tearDown()
  }
}

extension EchoServerTests {
  func testUnary() {
    XCTAssertEqual("Swift echo get: foo", try! client.get(Echo_EchoRequest(text: "foo")).text)
  }

  func testUnaryLotsOfRequests() {
    // Sending that many requests at once can sometimes trip things up, it seems.
    client.timeout = 5.0
    let clockStart = clock()
    let numberOfRequests = 1_000  //! FIXME: If we set this higher, it causes a crash related to `StreamManager.maxCachedStreamIDs`.
    for i in 0..<numberOfRequests {
      if i % 1_000 == 0 && i > 0 {
        print("\(i) requests sent so far, elapsed time: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
      }
      XCTAssertEqual("Swift echo get: foo \(i)", try client.get(Echo_EchoRequest(text: "foo \(i)")).text)
    }
    print("total time for \(numberOfRequests) requests: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
  }
}

extension EchoServerTests {
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

    for string in EchoServerTests.lotsOfStrings {
      let sendExpectation = expectation(description: "send completion handler \(string) called")
      try! call.send(Echo_EchoRequest(text: string)) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    }
    call.waitForSendOperationsToFinish()

    let response = try! call.closeAndReceive()
    XCTAssertEqual("Swift echo collect: " + EchoServerTests.lotsOfStrings.joined(separator: " "), response.text)

    waitForExpectations(timeout: defaultTimeout)
  }
}

extension EchoServerTests {
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
    let call = try! client.expand(Echo_EchoRequest(text: EchoServerTests.lotsOfStrings.joined(separator: " "))) { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }

    for string in EchoServerTests.lotsOfStrings {
      XCTAssertEqual("Swift echo expand (\(string)): \(string)", try! call.receive()!.text)
    }
    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }
}

extension EchoServerTests {
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
    //! FIXME: Fix this test.
    return
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

    call.waitForSendOperationsToFinish()

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

    for string in EchoServerTests.lotsOfStrings {
      let sendExpectation = expectation(description: "send completion handler \(string) called")
      try! call.send(Echo_EchoRequest(text: string)) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    }

    call.waitForSendOperationsToFinish()

    let closeCompletionHandlerExpectation = expectation(description: "close completion handler called")
    try! call.closeSend { closeCompletionHandlerExpectation.fulfill() }

    for string in EchoServerTests.lotsOfStrings {
      XCTAssertEqual("Swift echo update (\(string)): \(string)", try! call.receive()!.text)
    }
    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }

  func testBidirectionalStreamingLotsOfMessagesPingPong() {
    //! FIXME: Fix this test.
    return
    let finalCompletionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      finalCompletionHandlerExpectation.fulfill()
    }

    for string in EchoServerTests.lotsOfStrings {
      let sendExpectation = expectation(description: "send completion handler \(string) called")
      try! call.send(Echo_EchoRequest(text: string)) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
      XCTAssertEqual("Swift echo update (\(string)): \(string)", try! call.receive()!.text)
    }

    call.waitForSendOperationsToFinish()

    let closeCompletionHandlerExpectation = expectation(description: "close completion handler called")
    try! call.closeSend { closeCompletionHandlerExpectation.fulfill() }

    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }
}
