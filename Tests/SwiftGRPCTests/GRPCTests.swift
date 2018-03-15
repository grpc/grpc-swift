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
@testable import SwiftGRPC
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
    // We have more than ten entries here to ensure that even large metadata entries work
    // and aren't limited by e.g. a fixed-size entry buffer.
    "0": "zero",
    "1": "one",
    "2": "two",
    "3": "three",
    "4": "four",
    "5": "five",
    "6": "six",
    "7": "seven",
    "8": "eight",
    "9": "nine",
    "10": "ten",
    "11": "eleven",
    "12": "twelve"
]
let steps = 10
let hello = "/hello.unary"
let helloServerStream = "/hello.server-stream"
let helloBiDiStream = "/hello.bidi-stream"

// Return code/message for unary test
let oddStatusCode = StatusCode.ok
let oddStatusMessage = "OK"

let evenStatusCode = StatusCode.notFound
let eventStatusMessage = "Not Found"

func runTest(useSSL: Bool) {
  gRPC.initialize()

  var serverRunningSemaphore: DispatchSemaphore?

  // create the server
  let server: Server
  if useSSL {
    server = Server(address: address,
                    key: String(data: keyForTests, encoding: .utf8)!,
                    certs: String(data: certificateForTests, encoding: .utf8)!)
  } else {
    server = Server(address: address)
  }

  // start the server
  do {
    serverRunningSemaphore = try runServer(server: server)
  } catch (let error) {
    XCTFail("server error \(error)")
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
  _ = serverRunningSemaphore!.wait()
}

func verify_metadata(_ metadata: Metadata, expected: [String: String], file: StaticString = #file, line: UInt = #line) {
  XCTAssertGreaterThanOrEqual(metadata.count(), expected.count)
  var allPresentKeys = Set<String>()
  for i in 0..<metadata.count() {
    guard let expectedValue = expected[metadata.key(i)!]
      else { continue }
    allPresentKeys.insert(metadata.key(i)!)
    XCTAssertEqual(metadata.value(i), expectedValue, file: file, line: line)
  }
  XCTAssertEqual(allPresentKeys.sorted(), expected.keys.sorted(), file: file, line: line)
}

func runClient(useSSL: Bool) throws {
  let channel: Channel

  if useSSL {
    let certificateURL = URL(fileURLWithPath: "Tests/ssl.crt")
    guard
      let certificates = try? String(contentsOf: certificateURL, encoding: .utf8)
      else {
        return
    }
    channel = Channel(address: address, certificates: certificates, host: host)
  } else {
    channel = Channel(address: address, secure: false)
  }

  channel.host = host
  try callUnary(channel: channel)
  try callServerStream(channel: channel)
  try callBiDiStream(channel: channel)
}

func callUnary(channel: Channel) throws {
  let message = clientText.data(using: .utf8)

  for i in 0..<steps {
    let sem = DispatchSemaphore(value: 0)
    let method = hello
    let call = channel.makeCall(method)
    let metadata = Metadata(initialClientMetadata)
    try call.start(.unary, metadata: metadata, message: message) {
      response in
      // verify the basic response from the server
      XCTAssertEqual(response.statusCode, (i % 2  == 0) ? evenStatusCode : oddStatusCode)
      XCTAssertEqual(response.statusMessage, (i % 2  == 0) ? eventStatusMessage : oddStatusMessage)

      // verify the message from the server
      if (i % 2) == 0 {
        let resultData = response.resultData!
        let messageString = String(data: resultData, encoding: .utf8)
        XCTAssertEqual(messageString, serverText)
      }

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
    _ = sem.wait()
  }
}

func callServerStream(channel: Channel) throws {
  let message = clientText.data(using: .utf8)
  let metadata = Metadata(initialClientMetadata)

  let sem = DispatchSemaphore(value: 0)
  let method = helloServerStream
  let call = channel.makeCall(method)
  try call.start(.serverStreaming, metadata: metadata, message: message) {
    response in

    XCTAssertEqual(response.statusCode, StatusCode.outOfRange)
    XCTAssertEqual(response.statusMessage, "Out of range")

    // verify the trailing metadata from the server
    let trailingMetadata = response.trailingMetadata!
    verify_metadata(trailingMetadata, expected: trailingServerMetadata)

    sem.signal() // signal call is finished
  }

  for _ in 0..<steps {
    let messageSem = DispatchSemaphore(value: 0)
    try call.receiveMessage(completion: { callResult in
      if let data = callResult.resultData {
        let messageString = String(data: data, encoding: .utf8)
        XCTAssertEqual(messageString, serverText)
      } else {
        print("callServerStream unexpected result: \(callResult)")
      }
      messageSem.signal()
    })

    _ = messageSem.wait()
  }

  _ = sem.wait()
}

let clientPing = "ping"
let serverPong = "pong"

func callBiDiStream(channel: Channel) throws {
  let message = clientPing.data(using: .utf8)
  let metadata = Metadata(initialClientMetadata)

  let sem = DispatchSemaphore(value: 0)
  let method = helloBiDiStream
  let call = channel.makeCall(method)
  try call.start(.bidiStreaming, metadata: metadata, message: message) {
    response in

    XCTAssertEqual(response.statusCode, StatusCode.resourceExhausted)
    XCTAssertEqual(response.statusMessage, "Resource Exhausted")

    // verify the trailing metadata from the server
    let trailingMetadata = response.trailingMetadata!
    verify_metadata(trailingMetadata, expected: trailingServerMetadata)

    sem.signal() // signal call is finished
  }

  // Send pings
  for _ in 0..<steps {
    let message = clientPing.data(using: .utf8)
    try call.sendMessage(data: message!) { (err) in
      XCTAssertNil(err)
    }
    call.messageQueueEmpty.wait()
  }

  let closeSem = DispatchSemaphore(value: 0)
  try call.close {
    closeSem.signal()
  }
  _ = closeSem.wait()

  // Receive pongs
  for _ in 0..<steps {
    let pongSem = DispatchSemaphore(value: 0)
    try call.receiveMessage(completion: { callResult in
      if let data = callResult.resultData {
        let messageString = String(data: data, encoding: .utf8)
        XCTAssertEqual(messageString, serverPong)
      } else {
        print("callBiDiStream unexpected result: \(callResult)")
      }
      pongSem.signal()
    })
    _ = pongSem.wait()
  }

  _ = sem.wait()
}

func runServer(server: Server) throws -> DispatchSemaphore {
  var requestCount = 0
  let sem = DispatchSemaphore(value: 0)
  server.run { requestHandler in
    do {
      if let method = requestHandler.method {
        switch method {
        case hello:
          try handleUnary(requestHandler: requestHandler, requestCount: requestCount)
        case helloServerStream:
          try handleServerStream(requestHandler: requestHandler)
        case helloBiDiStream:
          try handleBiDiStream(requestHandler: requestHandler)
        default:
          XCTFail("Invalid method \(method)")
        }
      }

      requestCount += 1
    } catch (let error) {
      XCTFail("error \(error)")
    }
  }
  server.onCompletion = {
    // return from runServer()
    sem.signal()
  }
  // wait for the server to exit
  return sem
}

func handleUnary(requestHandler: Handler, requestCount: Int) throws {
  XCTAssertEqual(requestHandler.host, host)
  XCTAssertEqual(requestHandler.method, hello)
  let initialMetadata = requestHandler.requestMetadata
  verify_metadata(initialMetadata, expected: initialClientMetadata)
  let initialMetadataToSend = Metadata(initialServerMetadata)
  try requestHandler.receiveMessage(initialMetadata: initialMetadataToSend) { messageData in
    let messageString = String(data: messageData!, encoding: .utf8)
    XCTAssertEqual(messageString, clientText)
  }

  if (requestCount % 2) == 0 {
    let replyMessage = serverText
    let trailingMetadataToSend = Metadata(trailingServerMetadata)
    try requestHandler.sendResponse(message: replyMessage.data(using: .utf8)!,
                                    statusCode: evenStatusCode,
                                    statusMessage: eventStatusMessage,
                                    trailingMetadata: trailingMetadataToSend)
  } else {
    let trailingMetadataToSend = Metadata(trailingServerMetadata)
    try requestHandler.sendResponse(statusCode: oddStatusCode,
                                    statusMessage: oddStatusMessage,
                                    trailingMetadata: trailingMetadataToSend)
  }
}

func handleServerStream(requestHandler: Handler) throws {
  XCTAssertEqual(requestHandler.host, host)
  XCTAssertEqual(requestHandler.method, helloServerStream)
  let initialMetadata = requestHandler.requestMetadata
  verify_metadata(initialMetadata, expected: initialClientMetadata)

  let initialMetadataToSend = Metadata(initialServerMetadata)
  try requestHandler.receiveMessage(initialMetadata: initialMetadataToSend) { messageData in
    let messageString = String(data: messageData!, encoding: .utf8)
    XCTAssertEqual(messageString, clientText)
  }

  let replyMessage = serverText
  for _ in 0..<steps {
    try requestHandler.sendResponse(message: replyMessage.data(using: .utf8)!, completion: { (error) in
      XCTAssertNil(error)
    })
    requestHandler.call.messageQueueEmpty.wait()
  }

  let trailingMetadataToSend = Metadata(trailingServerMetadata)
  try requestHandler.sendStatus(statusCode: StatusCode.outOfRange,
                                statusMessage: "Out of range",
                                trailingMetadata: trailingMetadataToSend)
}

func handleBiDiStream(requestHandler: Handler) throws {
  XCTAssertEqual(requestHandler.host, host)
  XCTAssertEqual(requestHandler.method, helloBiDiStream)
  let initialMetadata = requestHandler.requestMetadata
  verify_metadata(initialMetadata, expected: initialClientMetadata)

  let initialMetadataToSend = Metadata(initialServerMetadata)
  let sendMetadataSem = DispatchSemaphore(value: 0)
  try requestHandler.sendMetadata(initialMetadata: initialMetadataToSend) { _ in
    _ = sendMetadataSem.signal()
  }
  _ = sendMetadataSem.wait()
  
  // Receive remaining pings
  for _ in 0..<steps {
    let receiveSem = DispatchSemaphore(value: 0)
    try requestHandler.receiveMessage(completion: { callStatus in
      let messageString = String(data: callStatus.resultData!, encoding: .utf8)
      XCTAssertEqual(messageString, clientPing)
      receiveSem.signal()
    })
    _ = receiveSem.wait()
  }

  // Send back pongs
  let replyMessage = serverPong.data(using: .utf8)!
  for _ in 0..<steps {
    try requestHandler.sendResponse(message: replyMessage, completion: { (error) in
      XCTAssertNil(error)
    })
    requestHandler.call.messageQueueEmpty.wait()
  }

  let trailingMetadataToSend = Metadata(trailingServerMetadata)
  let sem = DispatchSemaphore(value: 0)
  try requestHandler.sendStatus(statusCode: StatusCode.resourceExhausted,
                                statusMessage: "Resource Exhausted",
                                trailingMetadata: trailingMetadataToSend) { _ in sem.signal() }
  _ = sem.wait()
}
