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
import Dispatch
import Foundation
@testable import gRPC
import XCTest

class gRPCTests: XCTestCase {
  func testConnectivity() {
    runTest(useSSL: false)
  }

  func testConnectivitySecure() {
    runTest(useSSL: true)
  }

  static var allTests: [(String, (gRPCTests) -> () throws -> Void)] {
    return [
      ("testConnectivity", testConnectivity),
      ("testConnectivitySecure", testConnectivitySecure)
    ]
  }
}

let address = "localhost:8085"
let host = "example.com"
let clientText = "hello, server!"
let serverText = "hello, client!"
let initialClientMetadata =
  [
    "x": "xylophone",
    "y": "yu",
    "z": "zither"
  ]
let initialServerMetadata =
  [
    "a": "Apple",
    "b": "Banana",
    "c": "Cherry"
  ]
let trailingServerMetadata =
  [
    "0": "zero",
    "1": "one",
    "2": "two"
  ]
let steps = 10
let hello = "/hello"
let statusCode = StatusCode.ok
let statusMessage = "OK"

func runTest(useSSL: Bool) {
  gRPC.initialize()

  let serverRunningSemaphore = DispatchSemaphore(value: 0)

  // create the server
  var server: gRPC.Server!
  if useSSL {
    let certificateURL = URL(fileURLWithPath: "Tests/ssl.crt")
    let keyURL = URL(fileURLWithPath: "Tests/ssl.key")
    guard
      let certificate = try? String(contentsOf: certificateURL, encoding: .utf8),
      let key = try? String(contentsOf: keyURL, encoding: .utf8)
    else {
      return
    }
    server = gRPC.Server(address: address,
                         key: key,
                         certs: certificate)
  } else {
    server = gRPC.Server(address: address)
  }

  // start the server
  DispatchQueue.global().async {
    do {
      try runServer(server: server)
    } catch (let error) {
      XCTFail("server error \(error)")
    }
    serverRunningSemaphore.signal() // when the server exits, the test is finished
  }

  // run the client
  do {
    try runClient(useSSL: useSSL)
  } catch (let error) {
    XCTFail("client error \(error)")
  }

  // stop the server
  server.stop()

  // wait until the server has shut down
  _ = serverRunningSemaphore.wait(timeout: DispatchTime.distantFuture)
}

func verify_metadata(_ metadata: Metadata, expected: [String: String]) {
  XCTAssertGreaterThanOrEqual(metadata.count(), expected.count)
  for i in 0..<metadata.count() {
    if expected[metadata.key(i)] != nil {
      XCTAssertEqual(metadata.value(i), expected[metadata.key(i)])
    }
  }
}

func runClient(useSSL: Bool) throws {
  let message = clientText.data(using: .utf8)
  var channel: gRPC.Channel!

  if useSSL {
    let certificateURL = URL(fileURLWithPath: "Tests/ssl.crt")
    guard
      let certificates = try? String(contentsOf: certificateURL, encoding: .utf8)
    else {
      return
    }
    let host = "example.com"
    channel = gRPC.Channel(address: address, certificates: certificates, host: host)
  } else {
    channel = gRPC.Channel(address: address, secure: false)
  }

  channel.host = host
  for i in 0..<steps {
    let sem = DispatchSemaphore(value: 0)
    let method = hello
    let call = channel.makeCall(method)
    let metadata = Metadata(initialClientMetadata)
    try call.start(.unary, metadata: metadata, message: message) {
      response in
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
      sem.signal()
    }
    // wait for the call to complete
    _ = sem.wait(timeout: DispatchTime.distantFuture)
  }
}

func runServer(server: gRPC.Server) throws {
  var requestCount = 0
  let sem = DispatchSemaphore(value: 0)
  server.run { requestHandler in
    do {
      requestCount += 1
      XCTAssertEqual(requestHandler.host, host)
      XCTAssertEqual(requestHandler.method, hello)
      let initialMetadata = requestHandler.requestMetadata
      verify_metadata(initialMetadata, expected: initialClientMetadata)
      let initialMetadataToSend = Metadata(initialServerMetadata)
      try requestHandler.receiveMessage(initialMetadata: initialMetadataToSend) { messageData in
        let messageString = String(data: messageData!, encoding: .utf8)
        XCTAssertEqual(messageString, clientText)
      }
      let replyMessage = serverText
      let trailingMetadataToSend = Metadata(trailingServerMetadata)
      try requestHandler.sendResponse(message: replyMessage.data(using: .utf8)!,
                                      statusCode: statusCode,
                                      statusMessage: statusMessage,
                                      trailingMetadata: trailingMetadataToSend)
    } catch (let error) {
      XCTFail("error \(error)")
    }
  }
  server.onCompletion = {
    // return from runServer()
    sem.signal()
  }
  // wait for the server to exit
  _ = sem.wait(timeout: DispatchTime.distantFuture)
}
