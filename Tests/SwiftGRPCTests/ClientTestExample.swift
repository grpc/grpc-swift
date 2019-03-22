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
@testable import SwiftGRPC
import XCTest

// Sample test suite to demonstrate how one would test client code that
// uses an object that implements the `...Service` protocol.
// These tests don't really test the logic of the SwiftGRPC library, but are meant
// as an example of how one would go about testing their own client/server code that
// relies on SwiftGRPC.
fileprivate class ClientUnderTest {
  let service: Echo_EchoService

  init(service: Echo_EchoService) {
    self.service = service
  }

  func getWord(_ input: String) throws -> String {
    return try service.get(Echo_EchoRequest(text: input)).text
  }

  func collectWords(_ input: [String]) throws -> String {
    let call = try service.collect(completion: nil)
    for text in input {
      try call.send(Echo_EchoRequest(text: text), completion: { _ in })
    }
    call.waitForSendOperationsToFinish()
    return try call.closeAndReceive().text
  }

  func expandWords(_ input: String) throws -> [String] {
    let call = try service.expand(Echo_EchoRequest(text: input), completion: nil)
    var results: [String] = []
    while let response = try call.receive() {
      results.append(response.text)
    }
    return results
  }

  func updateWords(_ input: [String]) throws -> [String] {
    let call = try service.update(completion: nil)
    for text in input {
      try call.send(Echo_EchoRequest(text: text), completion: { _ in })
    }
    call.waitForSendOperationsToFinish()

    var results: [String] = []
    while let response = try call.receive() {
      results.append(response.text)
    }
    return results
  }
}

class ClientTestExample: XCTestCase { }

extension ClientTestExample {
  func testUnary() {
    let fakeService = Echo_EchoServiceTestStub()
    fakeService.getResponses.append(Echo_EchoResponse(text: "bar"))

    let client = ClientUnderTest(service: fakeService)
    XCTAssertEqual("bar", try client.getWord("foo"))

    // Ensure that all responses have been consumed.
    XCTAssertEqual(0, fakeService.getResponses.count)
    // Ensure that the expected requests have been sent.
    XCTAssertEqual([Echo_EchoRequest(text: "foo")], fakeService.getRequests)
  }

  func testClientStreaming() {
    let inputStrings = ["foo", "bar", "baz"]
    let fakeService = Echo_EchoServiceTestStub()
    let fakeCall = Echo_EchoCollectCallTestStub()
    fakeCall.output = Echo_EchoResponse(text: "response")
    fakeService.collectCalls.append(fakeCall)

    let client = ClientUnderTest(service: fakeService)
    XCTAssertEqual("response", try client.collectWords(inputStrings))

    // Ensure that the expected requests have been sent.
    XCTAssertEqual(inputStrings.map { Echo_EchoRequest(text: $0) }, fakeCall.inputs)
  }

  func testServerStreaming() {
    let outputStrings = ["foo", "bar", "baz"]
    let fakeService = Echo_EchoServiceTestStub()
    let fakeCall = Echo_EchoExpandCallTestStub()
    fakeCall.outputs = outputStrings.map { Echo_EchoResponse(text: $0) }
    fakeService.expandCalls.append(fakeCall)

    let client = ClientUnderTest(service: fakeService)
    XCTAssertEqual(outputStrings, try client.expandWords("inputWord"))

    // Ensure that all responses have been consumed.
    XCTAssertEqual(0, fakeCall.outputs.count)
    // Ensure that the expected requests have been sent.
    XCTAssertEqual([Echo_EchoRequest(text: "inputWord")], fakeService.expandRequests)
  }

  func testBidirectionalStreaming() {
    let inputStrings = ["foo", "bar", "baz"]
    let outputStrings = ["foo2", "bar2", "baz2"]
    let fakeService = Echo_EchoServiceTestStub()
    let fakeCall = Echo_EchoUpdateCallTestStub()
    fakeCall.outputs = outputStrings.map { Echo_EchoResponse(text: $0) }
    fakeService.updateCalls.append(fakeCall)

    let client = ClientUnderTest(service: fakeService)
    XCTAssertEqual(outputStrings, try client.updateWords(inputStrings))

    // Ensure that all responses have been consumed.
    XCTAssertEqual(0, fakeCall.outputs.count)
    // Ensure that the expected requests have been sent.
    XCTAssertEqual(inputStrings.map { Echo_EchoRequest(text: $0) }, fakeCall.inputs)
  }
}
