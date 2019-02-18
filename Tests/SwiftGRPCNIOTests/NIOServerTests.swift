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
        endOfSendOperationQueue = endOfSendOperationQueue.then {
          context.sendResponse(response)
        }
        count += 1

      case .end:
        endOfSendOperationQueue
          .map { GRPCStatus.ok }
          .cascade(promise: context.statusPromise)
      }
    })
  }
}

class NIOServerTests: NIOBasicEchoTestCase {
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

  static let aFewStrings = ["foo", "bar", "baz"]
  static let lotsOfStrings = (0..<10_000).map { String(describing: $0) }
}

extension NIOServerTests {
  func testUnary() throws {
    let options = CallOptions(timeout: nil)
    XCTAssertEqual(try client.get(Echo_EchoRequest.with { $0.text = "foo" }, callOptions: options).response.wait().text, "Swift echo get: foo")
  }

  func testUnaryLotsOfRequests() throws {
    // Sending that many requests at once can sometimes trip things up, it seems.
    let clockStart = clock()
    let numberOfRequests = 2_000

    for i in 0..<numberOfRequests {
      if i % 1_000 == 0 && i > 0 {
        print("\(i) requests sent so far, elapsed time: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
      }
      XCTAssertEqual(try client.get(Echo_EchoRequest.with { $0.text = "foo \(i)" }).response.wait().text, "Swift echo get: foo \(i)")
    }
    print("total time for \(numberOfRequests) requests: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
  }
}

extension NIOServerTests {
  func doTestClientStreaming(messages: [String]) throws {
    let call = client.collect()

    for message in messages {
      call.send(.message(Echo_EchoRequest.with { $0.text = message }))
    }
    call.send(.end)

    XCTAssertEqual("Swift echo collect: " + messages.joined(separator: " "), try call.response.wait().text)
    XCTAssertEqual(.ok, try call.status.wait().code)
  }

  func testClientStreaming() {
    XCTAssertNoThrow(try doTestClientStreaming(messages: NIOServerTests.aFewStrings))
  }

  func testClientStreamingLotsOfMessages() throws {
    XCTAssertNoThrow(try doTestClientStreaming(messages: NIOServerTests.lotsOfStrings))
  }
}

extension NIOServerTests {
  func doTestServerStreaming(messages: [String]) throws {
    var index = 0
    let call = client.expand(Echo_EchoRequest.with { $0.text = messages.joined(separator: " ") }) { response in
      XCTAssertEqual("Swift echo expand (\(index)): \(messages[index])", response.text)
      index += 1
    }

    XCTAssertEqual(try call.status.wait().code, .ok)
  }

  func testServerStreaming() {
    XCTAssertNoThrow(try doTestServerStreaming(messages: NIOServerTests.aFewStrings))
  }

  func testServerStreamingLotsOfMessages() {
    XCTAssertNoThrow(try doTestServerStreaming(messages: NIOServerTests.lotsOfStrings))
  }
}

extension NIOServerTests {
  private func doTestBidirectionalStreaming(messages: [String], waitForEachResponse: Bool = false) throws {
    let responseReceived = waitForEachResponse ? DispatchSemaphore(value: 0) : nil
    var index = 0

    let call = client.update { response in
      XCTAssertEqual("Swift echo update (\(index)): \(messages[index])", response.text)
      responseReceived?.signal()
      index += 1
    }

    messages.forEach { part in
      call.send(.message(Echo_EchoRequest.with { $0.text = part }))
      responseReceived?.wait()
    }
    call.send(.end)

    XCTAssertEqual(try call.status.wait().code, .ok)
  }

  func testBidirectionalStreamingBatched() throws {
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: NIOServerTests.aFewStrings))
  }

  func testBidirectionalStreamingPingPong() throws {
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: NIOServerTests.aFewStrings, waitForEachResponse: true))
  }

  func testBidirectionalStreamingLotsOfMessagesBatched() throws {
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: NIOServerTests.lotsOfStrings))
  }

  func testBidirectionalStreamingLotsOfMessagesPingPong() throws {
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: NIOServerTests.lotsOfStrings, waitForEachResponse: true))
  }
}
