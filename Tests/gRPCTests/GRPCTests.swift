/*
 * Copyright 2017, gRPC Authors All rights reserved.
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
import XCTest
import Foundation
import Dispatch
@testable import gRPC

func Log(_ message : String) {
  FileHandle.standardError.write((message + "\n").data(using:.utf8)!)
}

class gRPCTests: XCTestCase {

  func testBasicSanity() {
    gRPC.initialize()
    let latch = CountDownLatch(2)
    DispatchQueue.global().async() {
      do {
        try server()
      } catch (let error) {
        XCTFail("server error \(error)")
      }
      latch.signal()
    }
    DispatchQueue.global().async() {
      do {
        try client()
      } catch (let error) {
        XCTFail("client error \(error)")
      }
      latch.signal()
    }
    latch.wait()
  }
}

extension gRPCTests {
  static var allTests : [(String, (gRPCTests) -> () throws -> Void)] {
    return [
      ("testBasicSanity", testBasicSanity),
    ]
  }
}

let address = "localhost:8999"
let host = "foo.test.google.fr"
let clientText = "hello, server!"
let serverText = "hello, client!"
let initialClientMetadata =
  ["x": "xylophone",
   "y": "yu",
   "z": "zither"]
let initialServerMetadata =
  ["a": "Apple",
   "b": "Banana",
   "c": "Cherry"]
let trailingServerMetadata =
  ["0": "zero",
   "1": "one",
   "2": "two"]
let steps = 30
let hello = "/hello"
let goodbye = "/goodbye"
let statusCode = 0
let statusMessage = "OK"

func verify_metadata(_ metadata: Metadata, expected: [String:String]) {
  XCTAssertGreaterThanOrEqual(metadata.count(), expected.count)
  for i in 0..<metadata.count() {
    if expected[metadata.key(i)] != nil {
      XCTAssertEqual(metadata.value(i), expected[metadata.key(i)])
    }
  }
}

func client() throws {
  let message = clientText.data(using: .utf8)
  let channel = gRPC.Channel(address:address)
  channel.host = host
  for i in 0..<steps {
    let latch = CountDownLatch(1)
    let method = (i < steps-1) ? hello : goodbye
    let call = channel.makeCall(method)
    let metadata = Metadata(initialClientMetadata)
    try call.start(.unary, metadata:metadata, message:message) {
      (response) in
      // verify the basic response from the server
      XCTAssertEqual(response.statusCode, statusCode)
      XCTAssertEqual(response.statusMessage, statusMessage)
      // verify the message from the server
      let resultData = response.resultData
      let messageString = String(data: resultData!, encoding: .utf8)
      XCTAssertEqual(messageString, serverText)
      // verify the initial metadata from the server
      let initialMetadata = response.initialMetadata!
      verify_metadata(initialMetadata, expected: initialServerMetadata)
      // verify the trailing metadata from the server
      let trailingMetadata = response.trailingMetadata!
      verify_metadata(trailingMetadata, expected: trailingServerMetadata)
      // report completion
      latch.signal()
    }
    // wait for the call to complete
    latch.wait()
  }
  usleep(500) // temporarily delay calls to the channel destructor
}

func server() throws {
  let server = gRPC.Server(address:address)
  var requestCount = 0
  let latch = CountDownLatch(1)
  server.run() {(requestHandler) in
    do {
      requestCount += 1
      XCTAssertEqual(requestHandler.host, host)
      if (requestCount < steps) {
        XCTAssertEqual(requestHandler.method, hello)
      } else {
        XCTAssertEqual(requestHandler.method, goodbye)
      }
      let initialMetadata = requestHandler.requestMetadata
      verify_metadata(initialMetadata, expected: initialClientMetadata)
      let initialMetadataToSend = Metadata(initialServerMetadata)
      try requestHandler.receiveMessage(initialMetadata:initialMetadataToSend)
      {(messageData) in
        let messageString = String(data: messageData!, encoding: .utf8)
        XCTAssertEqual(messageString, clientText)
      }
      if requestHandler.method == goodbye {
        server.stop()
      }
      let replyMessage = serverText
      let trailingMetadataToSend = Metadata(trailingServerMetadata)
      try requestHandler.sendResponse(message:replyMessage.data(using: .utf8)!,
                                      statusCode:statusCode,
                                      statusMessage:statusMessage,
                                      trailingMetadata:trailingMetadataToSend)
    } catch (let error) {
      XCTFail("error \(error)")
    }
  }
  server.onCompletion() {
    // exit the server thread
    latch.signal()
  }
  // wait for the server to exit
  latch.wait()
}
