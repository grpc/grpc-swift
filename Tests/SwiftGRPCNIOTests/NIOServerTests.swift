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

class NIOServerTests: NIOBasicEchoTestCase {
  static var allTests: [(String, (NIOServerTests) -> () throws -> Void)] {
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

  static let aFewStrings = ["foo", "bar", "baz"]
  static let lotsOfStrings = (0..<5_000).map { String(describing: $0) }
}

extension NIOServerTests {
  func testUnary() throws {
    XCTAssertEqual(try client.get(Echo_EchoRequest(text: "foo")).response.wait().text, "Swift echo get: foo")
  }

  func testUnaryLotsOfRequests() throws {
    // Sending that many requests at once can sometimes trip things up, it seems.
    let clockStart = clock()
    let numberOfRequests = 2_000

    for i in 0..<numberOfRequests {
      if i % 1_000 == 0 && i > 0 {
        print("\(i) requests sent so far, elapsed time: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
      }
      XCTAssertEqual(try client.get(Echo_EchoRequest(text: "foo \(i)")).response.wait().text, "Swift echo get: foo \(i)")
    }
    print("total time for \(numberOfRequests) requests: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
  }

  func testUnaryWithLargeData() throws {
    // Default max frame size is: 16,384. We'll exceed this as we also have to send the size and compression flag.
    let longMessage = String(repeating: "e", count: 16_384)
    XCTAssertEqual(try client.get(Echo_EchoRequest(text: longMessage)).response.wait().text, "Swift echo get: \(longMessage)")
  }

  func testUnaryEmptyRequest() throws {
    XCTAssertNoThrow(try client.get(Echo_EchoRequest()).response.wait())
  }
}

extension NIOServerTests {
  func doTestClientStreaming(messages: [String], file: StaticString = #file, line: UInt = #line) throws {
    let call = client.collect()

    var queue = call.newMessageQueue()
    for message in messages {
      queue = queue.then { call.sendMessage(Echo_EchoRequest(text: message)) }
    }
    queue.whenSuccess { call.sendEnd(promise: nil) }

    XCTAssertEqual("Swift echo collect: " + messages.joined(separator: " "), try call.response.wait().text, file: file, line: line)
    XCTAssertEqual(.ok, try call.status.wait().code, file: file, line: line)
  }

  func testClientStreaming() {
    XCTAssertNoThrow(try doTestClientStreaming(messages: NIOServerTests.aFewStrings))
  }

  func testClientStreamingLotsOfMessages() throws {
    XCTAssertNoThrow(try doTestClientStreaming(messages: NIOServerTests.lotsOfStrings))
  }
}

extension NIOServerTests {
  func doTestServerStreaming(messages: [String], file: StaticString = #file, line: UInt = #line) throws {
    var index = 0
    let call = client.expand(Echo_EchoRequest.with { $0.text = messages.joined(separator: " ") }) { response in
      XCTAssertEqual("Swift echo expand (\(index)): \(messages[index])", response.text, file: file, line: line)
      index += 1
    }

    XCTAssertEqual(try call.status.wait().code, .ok, file: file, line: line)
    XCTAssertEqual(index, messages.count)
  }

  func testServerStreaming() {
    XCTAssertNoThrow(try doTestServerStreaming(messages: NIOServerTests.aFewStrings))
  }

  func testServerStreamingLotsOfMessages() {
    XCTAssertNoThrow(try doTestServerStreaming(messages: NIOServerTests.lotsOfStrings))
  }
}

extension NIOServerTests {
  private func doTestBidirectionalStreaming(messages: [String], waitForEachResponse: Bool = false, timeout: GRPCTimeout? = nil, file: StaticString = #file, line: UInt = #line) throws {
    let responseReceived = waitForEachResponse ? DispatchSemaphore(value: 0) : nil
    var index = 0

    let callOptions = timeout.map { CallOptions(timeout: $0) }
    let call = client.update(callOptions: callOptions) { response in
      XCTAssertEqual("Swift echo update (\(index)): \(messages[index])", response.text, file: file, line: line)
      responseReceived?.signal()
      index += 1
    }

    messages.forEach { part in
      call.sendMessage(Echo_EchoRequest(text: part), promise: nil)
      XCTAssertNotEqual(responseReceived?.wait(timeout: .now() + .seconds(1)), .some(.timedOut), file: file, line: line)
    }
    call.sendEnd(promise: nil)

    XCTAssertEqual(try call.status.wait().code, .ok, file: file, line: line)
    XCTAssertEqual(index, messages.count)
  }

  func testBidirectionalStreamingBatched() throws {
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: NIOServerTests.aFewStrings))
  }

  func testBidirectionalStreamingPingPong() throws {
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: NIOServerTests.aFewStrings, waitForEachResponse: true))
  }

  func testBidirectionalStreamingLotsOfMessagesBatched() throws {
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: NIOServerTests.lotsOfStrings, timeout: try .seconds(15)))
  }

  func testBidirectionalStreamingLotsOfMessagesPingPong() throws {
    XCTAssertNoThrow(try doTestBidirectionalStreaming(messages: NIOServerTests.lotsOfStrings, waitForEachResponse: true, timeout: try .seconds(15)))
  }
}
