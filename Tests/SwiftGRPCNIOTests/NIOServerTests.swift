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
final class EchoProvider_NIO: Echo_EchoProvider_NIO {
  func get(request: Echo_EchoRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Echo_EchoResponse> {
    var response = Echo_EchoResponse()
    response.text = "Swift echo get: " + request.text
    return context.eventLoop.newSucceededFuture(result: response)
  }

  func collect(context: UnaryResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    var parts: [String] = []
    return context.eventLoop.newSucceededFuture(result: { event in
      switch event {
      case .message(let message):
        parts.append(message.text)

      case .end:
        var response = Echo_EchoResponse()
        response.text = "Swift echo collect: " + parts.joined(separator: " ")
        context.responsePromise.succeed(result: response)
      }
    })
  }

  func expand(request: Echo_EchoRequest, context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<GRPCStatus> {
    var endOfSendOperationQueue = context.eventLoop.newSucceededFuture(result: ())
    let parts = request.text.components(separatedBy: " ")
    for (i, part) in parts.enumerated() {
      var response = Echo_EchoResponse()
      response.text = "Swift echo expand (\(i)): \(part)"
      endOfSendOperationQueue = endOfSendOperationQueue.then { context.sendResponse(response) }
    }
    return endOfSendOperationQueue.map { GRPCStatus.ok }
  }

  func update(context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    var endOfSendOperationQueue = context.eventLoop.newSucceededFuture(result: ())
    var count = 0
    return context.eventLoop.newSucceededFuture(result: { event in
      switch event {
      case .message(let message):
        var response = Echo_EchoResponse()
        response.text = "Swift echo update (\(count)): \(message.text)"
        endOfSendOperationQueue = endOfSendOperationQueue.then { context.sendResponse(response) }
        count += 1

      case .end:
        endOfSendOperationQueue
          .map { GRPCStatus.ok }
          .cascade(promise: context.statusPromise)
      }
    })
  }
}

class NIOServerTests: NIOServerTestCase {
  static var allTests: [(String, (NIOServerTests) -> () throws -> Void)] {
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
    eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    server = try! GRPCServer.start(
      hostname: "localhost", port: 5050, eventLoopGroup: eventLoopGroup, serviceProviders: [EchoProvider_NIO()])
      .wait()
  }

  override func tearDown() {
    XCTAssertNoThrow(try server.close().wait())

    XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
    eventLoopGroup = nil

    super.tearDown()
  }
}

extension NIOServerTests {
  func testUnary() {
    XCTAssertEqual("Swift echo get: foo", try! client.get(Echo_EchoRequest(text: "foo")).text)
  }

  func testUnaryWithLargeData() throws {
    // Default max frame size is: 16,384. We'll exceed this as we also have to send the size and compression flag.
    let longMessage = String(repeating: "e", count: 16_384)
    XCTAssertNoThrow(try client.get(Echo_EchoRequest(text: longMessage))) { response in
      XCTAssertEqual("Swift echo get: \(longMessage)", response.text)
    }
  }

  func testUnaryLotsOfRequests() {
    // Sending that many requests at once can sometimes trip things up, it seems.
    client.timeout = 5.0
    let clockStart = clock()
    let numberOfRequests = 2_000
    for i in 0..<numberOfRequests {
      if i % 1_000 == 0 && i > 0 {
        print("\(i) requests sent so far, elapsed time: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
      }
      XCTAssertEqual("Swift echo get: foo \(i)", try client.get(Echo_EchoRequest(text: "foo \(i)")).text)
    }
    print("total time for \(numberOfRequests) requests: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
  }

  func testUnaryEmptyRequest() throws {
    XCTAssertNoThrow(try client.get(Echo_EchoRequest()))
  }
}

extension NIOServerTests {
  func testClientStreaming() {
    let completionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.collect { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }

    XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: "foo")))
    XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: "bar")))
    XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: "baz")))
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

    for string in NIOServerTests.lotsOfStrings {
      XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: string)))
    }
    call.waitForSendOperationsToFinish()

    let response = try! call.closeAndReceive()
    XCTAssertEqual("Swift echo collect: " + NIOServerTests.lotsOfStrings.joined(separator: " "), response.text)

    waitForExpectations(timeout: defaultTimeout)
  }
}

extension NIOServerTests {
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
    let call = try! client.expand(Echo_EchoRequest(text: NIOServerTests.lotsOfStrings.joined(separator: " "))) { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }

    for string in NIOServerTests.lotsOfStrings {
      XCTAssertEqual("Swift echo expand (\(string)): \(string)", try! call.receive()!.text)
    }
    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }
}

extension NIOServerTests {
  func testBidirectionalStreamingBatched() {
    let finalCompletionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      finalCompletionHandlerExpectation.fulfill()
    }

    XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: "foo")))
    XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: "bar")))
    XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: "baz")))

    call.waitForSendOperationsToFinish()

    XCTAssertNoThrow(try call.closeSend())

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

    XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: "foo")))
    XCTAssertEqual("Swift echo update (0): foo", try! call.receive()!.text)

    XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: "bar")))
    XCTAssertEqual("Swift echo update (1): bar", try! call.receive()!.text)

    XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: "baz")))
    XCTAssertEqual("Swift echo update (2): baz", try! call.receive()!.text)

    call.waitForSendOperationsToFinish()

    XCTAssertNoThrow(try call.closeSend())

    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }

  func testBidirectionalStreamingLotsOfMessagesBatched() {
    let finalCompletionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      finalCompletionHandlerExpectation.fulfill()
    }

    for string in NIOServerTests.lotsOfStrings {
      XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: string)))
    }

    call.waitForSendOperationsToFinish()

    XCTAssertNoThrow(try call.closeSend())

    for string in NIOServerTests.lotsOfStrings {
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

    for string in NIOServerTests.lotsOfStrings {
      XCTAssertNoThrow(try call.send(Echo_EchoRequest(text: string)))
      XCTAssertEqual("Swift echo update (\(string)): \(string)", try! call.receive()!.text)
    }

    call.waitForSendOperationsToFinish()

    XCTAssertNoThrow(try call.closeSend())

    XCTAssertNil(try! call.receive())

    waitForExpectations(timeout: defaultTimeout)
  }
}
