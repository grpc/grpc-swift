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
  // We have seen this test flake out in rare cases fairly often due to race conditions.
  // To detect such rare errors, we run the tests several times.
  // (By now, all known errors should have been fixed, but we'd still like to detect new ones.)
  let testRepetitions = 10

  func testConnectivity() {
    for _ in 0..<testRepetitions {
      runTest(useSSL: false)
    }
  }

  func testConnectivitySecure() {
    for _ in 0..<testRepetitions {
      runTest(useSSL: true)
    }
  }
}

let address = "localhost:8085"
let host = "example.com"
let evenClientText = "hello, server!"
let oddClientText = "hello, server, please fail!"
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
let steps = 100
let hello = "/hello.unary"
let helloServerStream = "/hello.server-stream"
let helloBiDiStream = "/hello.bidi-stream"

// Return code/message for unary test
let oddStatusMessage = "OK"
let evenStatusMessage = "some other status message"

// Parsing very large messages as String is very inefficient,
// so we avoid it anything above this threshold.
let sizeThresholdForReturningDataVerbatim = 10_000

func runTest(useSSL: Bool) {
  gRPC.initialize()

  var serverRunningSemaphore: DispatchSemaphore?

  // create the server
  let server: Server
  if useSSL {
    server = Server(address: address,
                    key: String(data: serverKey, encoding: .utf8)!,
                    certs: String(data: serverCertificate, encoding: .utf8)!)
  } else {
    server = Server(address: address)
  }

  // start the server
  do {
    serverRunningSemaphore = try runServer(server: server)
  } catch {
    XCTFail("server error \(error)")
  }

  // run the client
  do {
    try runClient(useSSL: useSSL)
  } catch {
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
    channel = Channel(address: address,
                      certificates: String(data: trustCollectionCertificate, encoding: .utf8)!,
                      arguments: [.sslTargetNameOverride(host)])
  } else {
    channel = Channel(address: address, secure: false)
  }

  channel.host = host
  let largeMessage = Data(repeating: 88 /* 'X' */, count: 4_000_000)
  for _ in 0..<10 {
    // Send several calls to each server we spin up, to ensure that each individual server can handle many requests.
    try callUnary(channel: channel)
    try callServerStream(channel: channel)
    try callBiDiStream(channel: channel)
  }
  // Test sending a large message.
  try callUnaryIndividual(channel: channel, message: largeMessage, shouldSucceed: true)
  try callUnaryIndividual(channel: channel, message: largeMessage, shouldSucceed: true)
}

func callUnary(channel: Channel) throws {
  let evenMessage = evenClientText.data(using: .utf8)!
  let oddMessage = oddClientText.data(using: .utf8)!
  for i in 0..<steps {
    try callUnaryIndividual(channel: channel,
                            message: (i % 2) == 0 ? evenMessage : oddMessage,
                            shouldSucceed: (i % 2) == 0)
  }
}

func callUnaryIndividual(channel: Channel, message: Data, shouldSucceed: Bool) throws {
  let sem = DispatchSemaphore(value: 0)
  let method = hello
  let call = try channel.makeCall(method)
  let metadata = try Metadata(initialClientMetadata)
  try call.start(.unary, metadata: metadata, message: message) {
    response in
    // verify the basic response from the server
    XCTAssertEqual(response.statusCode, .ok)
    XCTAssertEqual(response.statusMessage, shouldSucceed ? evenStatusMessage : oddStatusMessage)

    //print("response.resultData?.count", response.resultData?.count)

    // verify the message from the server
    if shouldSucceed {
      if let resultData = response.resultData {
        if resultData.count >= sizeThresholdForReturningDataVerbatim {
          XCTAssertEqual(message, resultData)
        } else {
          let messageString = String(data: resultData, encoding: .utf8)
          XCTAssertEqual(messageString, serverText)
        }
      } else {
        XCTFail("callUnary response missing")
      }
    }

    // verify the initial metadata from the server
    if let initialMetadata = response.initialMetadata {
      verify_metadata(initialMetadata, expected: initialServerMetadata)
    } else {
      XCTFail("callUnary initial metadata missing")
    }

    // verify the trailing metadata from the server
    if let trailingMetadata = response.trailingMetadata {
      verify_metadata(trailingMetadata, expected: trailingServerMetadata)
    } else {
      XCTFail("callUnary trailing metadata missing")
    }

    // report completion
    sem.signal()
  }
  // wait for the call to complete
  _ = sem.wait()
}

func callServerStream(channel: Channel) throws {
  let message = evenClientText.data(using: .utf8)
  let metadata = try Metadata(initialClientMetadata)

  let sem = DispatchSemaphore(value: 0)
  let method = helloServerStream
  let call = try channel.makeCall(method)
  try call.start(.serverStreaming, metadata: metadata, message: message) {
    response in

    XCTAssertEqual(response.statusCode, .ok)
    XCTAssertEqual(response.statusMessage, "Custom Status Message ServerStreaming")

    // verify the trailing metadata from the server
    if let trailingMetadata = response.trailingMetadata {
      verify_metadata(trailingMetadata, expected: trailingServerMetadata)
    } else {
      XCTFail("callServerStream trailing metadata missing")
    }

    sem.signal() // signal call is finished
  }

  for _ in 0..<steps {
    let messageSem = DispatchSemaphore(value: 0)
    try call.receiveMessage { callResult in
      if let data = callResult.resultData {
        let messageString = String(data: data, encoding: .utf8)
        XCTAssertEqual(messageString, serverText)
      } else {
        XCTFail("callServerStream unexpected result: \(callResult)")
      }
      messageSem.signal()
    }
    _ = messageSem.wait()
  }

  _ = sem.wait()
}

let clientPing = "ping"
let serverPong = "pong"

func callBiDiStream(channel: Channel) throws {
  let metadata = try Metadata(initialClientMetadata)

  let sem = DispatchSemaphore(value: 0)
  let method = helloBiDiStream
  let call = try channel.makeCall(method)
  try call.start(.bidiStreaming, metadata: metadata, message: nil) {
    response in

    XCTAssertEqual(response.statusCode, .ok)
    XCTAssertEqual(response.statusMessage, "Custom Status Message BiDi")

    // verify the trailing metadata from the server
    if let trailingMetadata = response.trailingMetadata {
      verify_metadata(trailingMetadata, expected: trailingServerMetadata)
    } else {
      XCTFail("callBiDiStream trailing metadata missing")
    }

    sem.signal() // signal call is finished
  }

  // Send pings
  let message = clientPing.data(using: .utf8)!
  for _ in 0..<steps {
    try call.sendMessage(data: message) { err in
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
    try call.receiveMessage { callResult in
      if let data = callResult.resultData {
        let messageString = String(data: data, encoding: .utf8)
        XCTAssertEqual(messageString, serverPong)
      } else {
        XCTFail("callBiDiStream unexpected result: \(callResult)")
      }
      pongSem.signal()
    }
    _ = pongSem.wait()
  }

  _ = sem.wait()
}

func runServer(server: Server) throws -> DispatchSemaphore {
  let sem = DispatchSemaphore(value: 0)
  server.run { requestHandler in
    do {
      if let method = requestHandler.method {
        switch method {
        case hello:
          try handleUnary(requestHandler: requestHandler)
        case helloServerStream:
          try handleServerStream(requestHandler: requestHandler)
        case helloBiDiStream:
          try handleBiDiStream(requestHandler: requestHandler)
        default:
          XCTFail("Invalid method \(method)")
        }
      }
    } catch {
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

func handleUnary(requestHandler: Handler) throws {
  XCTAssertEqual(requestHandler.host, host)
  XCTAssertEqual(requestHandler.method, hello)
  let initialMetadata = requestHandler.requestMetadata
  verify_metadata(initialMetadata, expected: initialClientMetadata)
  let initialMetadataToSend = try Metadata(initialServerMetadata)
  let receiveSem = DispatchSemaphore(value: 0)
  var inputMessage: Data?
  try requestHandler.receiveMessage(initialMetadata: initialMetadataToSend) {
    if let messageData = $0 {
      inputMessage = messageData
      if messageData.count < sizeThresholdForReturningDataVerbatim {
        let messageString = String(data: messageData, encoding: .utf8)!
        XCTAssertTrue(messageString == evenClientText || messageString == oddClientText,
                      "handleUnary unexpected message string \(messageString)")
      }
    } else {
      XCTFail("handleUnary message missing")
    }
    receiveSem.signal()
  }
  receiveSem.wait()

  // We need to return status OK in both cases, as it seems like the server might never send out the last few messages
  // once it has been asked to send a non-OK status. Alternatively, we could send a non-OK status here, but then we
  // would need to sleep for a few milliseconds before sending the non-OK status.
  let replyMessage = (inputMessage == nil || inputMessage!.count < sizeThresholdForReturningDataVerbatim)
    ? serverText.data(using: .utf8)!
    : inputMessage!
  let trailingMetadataToSend = try Metadata(trailingServerMetadata)
  if let inputMessage = inputMessage,
    inputMessage.count >= sizeThresholdForReturningDataVerbatim
      || inputMessage == evenClientText.data(using: .utf8)! {
    try requestHandler.sendResponse(message: replyMessage,
                                    status: ServerStatus(code: .ok,
                                                         message: evenStatusMessage,
                                                         trailingMetadata: trailingMetadataToSend))
  } else {
    try requestHandler.sendStatus(ServerStatus(code: .ok,
                                               message: oddStatusMessage,
                                               trailingMetadata: trailingMetadataToSend))
  }
}

func handleServerStream(requestHandler: Handler) throws {
  XCTAssertEqual(requestHandler.host, host)
  XCTAssertEqual(requestHandler.method, helloServerStream)
  let initialMetadata = requestHandler.requestMetadata
  verify_metadata(initialMetadata, expected: initialClientMetadata)

  let initialMetadataToSend = try Metadata(initialServerMetadata)
  try requestHandler.receiveMessage(initialMetadata: initialMetadataToSend) {
    if let messageData = $0 {
      let messageString = String(data: messageData, encoding: .utf8)
      XCTAssertEqual(messageString, evenClientText)
    } else {
      XCTFail("handleServerStream message missing")
    }
  }

  let replyMessage = serverText.data(using: .utf8)!
  for _ in 0..<steps {
    try requestHandler.call.sendMessage(data: replyMessage) { error in
      XCTAssertNil(error)
    }
    requestHandler.call.messageQueueEmpty.wait()
  }

  let trailingMetadataToSend = try Metadata(trailingServerMetadata)
  try requestHandler.sendStatus(ServerStatus(
    // We need to return status OK here, as it seems like the server might never send out the last few messages once it
    // has been asked to send a non-OK status. Alternatively, we could send a non-OK status here, but then we would need
    // to sleep for a few milliseconds before sending the non-OK status.
    code: .ok,
    message: "Custom Status Message ServerStreaming",
    trailingMetadata: trailingMetadataToSend))
}

func handleBiDiStream(requestHandler: Handler) throws {
  XCTAssertEqual(requestHandler.host, host)
  XCTAssertEqual(requestHandler.method, helloBiDiStream)
  let initialMetadata = requestHandler.requestMetadata
  verify_metadata(initialMetadata, expected: initialClientMetadata)

  let initialMetadataToSend = try Metadata(initialServerMetadata)
  let sendMetadataSem = DispatchSemaphore(value: 0)
  try requestHandler.sendMetadata(initialMetadata: initialMetadataToSend) { _ in
    _ = sendMetadataSem.signal()
  }
  _ = sendMetadataSem.wait()

  // Receive remaining pings
  for _ in 0..<steps {
    let receiveSem = DispatchSemaphore(value: 0)
    try requestHandler.call.receiveMessage { callStatus in
      if let messageData = callStatus.resultData {
        let messageString = String(data: messageData, encoding: .utf8)
        XCTAssertEqual(messageString, clientPing)
      } else {
        XCTFail("handleBiDiStream message empty")
      }
      receiveSem.signal()
    }
    _ = receiveSem.wait()
  }

  // Send back pongs
  let replyMessage = serverPong.data(using: .utf8)!
  for _ in 0..<steps {
    try requestHandler.call.sendMessage(data: replyMessage) { error in
      XCTAssertNil(error)
    }
    requestHandler.call.messageQueueEmpty.wait()
  }

  let trailingMetadataToSend = try Metadata(trailingServerMetadata)
  let sem = DispatchSemaphore(value: 0)
  try requestHandler.sendStatus(ServerStatus(
    // We need to return status OK here, as it seems like the server might never send out the last few messages once it
    // has been asked to send a non-OK status. Alternatively, we could send a non-OK status here, but then we would need
    // to sleep for a few milliseconds before sending the non-OK status.
    code: .ok,
    message: "Custom Status Message BiDi",
    trailingMetadata: trailingMetadataToSend)) { sem.signal() }
  _ = sem.wait()
}
