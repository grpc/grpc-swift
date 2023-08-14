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
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import EchoModel
@testable import GRPC
import NIOCore
import XCTest

// Only test Unary and ServerStreaming, as ClientStreaming is not
// supported in HTTP1.
// TODO: Add tests for application/grpc-web as well.
class ServerWebTests: EchoTestCaseBase {
  private func gRPCEncodedEchoRequest(_ text: String) -> Data {
    var request = Echo_EchoRequest()
    request.text = text
    var data = try! request.serializedData()
    // Add the gRPC prefix with the compression byte and the 4 length bytes.
    for i in 0 ..< 4 {
      data.insert(UInt8((data.count >> (i * 8)) & 0xFF), at: 0)
    }
    data.insert(UInt8(0), at: 0)
    return data
  }

  private func gRPCWebTrailers(status: Int = 0, message: String? = nil) -> Data {
    var data: Data
    if let message = message {
      data = "grpc-status: \(status)\r\ngrpc-message: \(message)\r\n".data(using: .utf8)!
    } else {
      data = "grpc-status: \(status)\r\n".data(using: .utf8)!
    }

    // Add the gRPC prefix with the compression byte and the 4 length bytes.
    for i in 0 ..< 4 {
      data.insert(UInt8((data.count >> (i * 8)) & 0xFF), at: 0)
    }
    data.insert(UInt8(0x80), at: 0)
    return data
  }

  private func sendOverHTTP1(
    rpcMethod: String,
    message: String?,
    handler: @escaping (Data?, Error?) -> Void
  ) {
    let serverURL = URL(string: "http://localhost:\(self.port!)/echo.Echo/\(rpcMethod)")!
    var request = URLRequest(url: serverURL)
    request.httpMethod = "POST"
    request.setValue("application/grpc-web-text", forHTTPHeaderField: "content-type")

    if let message = message {
      request.httpBody = self.gRPCEncodedEchoRequest(message).base64EncodedData()
    }

    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, _, error in
      handler(data, error)
      sem.signal()
    }.resume()
    sem.wait()
  }
}

extension ServerWebTests {
  func testUnary() {
    let message = "hello, world!"
    let expectedData = self.gRPCEncodedEchoRequest("Swift echo get: \(message)") + self
      .gRPCWebTrailers()
    let expectedResponse = expectedData.base64EncodedString()

    let completionHandlerExpectation = expectation(description: "completion handler called")

    self.sendOverHTTP1(rpcMethod: "Get", message: message) { data, error in
      XCTAssertNil(error)
      if let data = data {
        XCTAssertEqual(String(data: data, encoding: .utf8), expectedResponse)
        completionHandlerExpectation.fulfill()
      } else {
        XCTFail("no data returned")
      }
    }

    waitForExpectations(timeout: defaultTestTimeout)
  }

  func testUnaryWithoutRequestMessage() {
    let expectedData = self.gRPCWebTrailers(
      status: 13,
      message: "Protocol violation: End received before message"
    )

    let expectedResponse = expectedData.base64EncodedString()

    let completionHandlerExpectation = expectation(description: "completion handler called")

    self.sendOverHTTP1(rpcMethod: "Get", message: nil) { data, error in
      XCTAssertNil(error)
      if let data = data {
        XCTAssertEqual(String(data: data, encoding: .utf8), expectedResponse)
        completionHandlerExpectation.fulfill()
      } else {
        XCTFail("no data returned")
      }
    }

    waitForExpectations(timeout: defaultTestTimeout)
  }

  func testUnaryLotsOfRequests() {
    guard self.runTimeSensitiveTests() else { return }
    // Sending that many requests at once can sometimes trip things up, it seems.
    let clockStart = clock()
    let numberOfRequests = 2000

    let completionHandlerExpectation = expectation(description: "completion handler called")
    completionHandlerExpectation.expectedFulfillmentCount = numberOfRequests
    completionHandlerExpectation.assertForOverFulfill = true

    for i in 0 ..< numberOfRequests {
      let message = "foo \(i)"
      let expectedData = self.gRPCEncodedEchoRequest("Swift echo get: \(message)") + self
        .gRPCWebTrailers()
      let expectedResponse = expectedData.base64EncodedString()
      self.sendOverHTTP1(rpcMethod: "Get", message: message) { data, error in
        XCTAssertNil(error)
        if let data = data {
          XCTAssertEqual(String(data: data, encoding: .utf8), expectedResponse)
          completionHandlerExpectation.fulfill()
        }
      }
    }
    waitForExpectations(timeout: 10)
    print(
      "total time for \(numberOfRequests) requests: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))"
    )
  }

  func testServerStreaming() {
    let message = "foo bar baz"

    var expectedData = Data()
    var index = 0
    message.split(separator: " ").forEach { component in
      expectedData.append(self.gRPCEncodedEchoRequest("Swift echo expand (\(index)): \(component)"))
      index += 1
    }
    expectedData.append(self.gRPCWebTrailers())
    let expectedResponse = expectedData.base64EncodedString()
    let completionHandlerExpectation = expectation(description: "completion handler called")

    self.sendOverHTTP1(rpcMethod: "Expand", message: message) { data, error in
      XCTAssertNil(error)
      if let data = data {
        XCTAssertEqual(String(data: data, encoding: .utf8), expectedResponse)
        completionHandlerExpectation.fulfill()
      }
    }

    waitForExpectations(timeout: defaultTestTimeout)
  }
}
