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
import NIO
@testable import SwiftGRPCNIO
import XCTest

// Only test Unary and ServerStreaming, as ClientStreaming is not
// supported in HTTP1.
// TODO: Add tests for application/grpc-web as well.
class NIOServerWebTests: NIOServerTestCase {
  static var allTests: [(String, (NIOServerWebTests) -> () throws -> Void)] {
    return [
      ("testUnary", testUnary),
      ("testUnaryLotsOfRequests", testUnaryLotsOfRequests),
      ("testServerStreaming", testServerStreaming),
    ]
  }

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

  private func gRPCEncodedEchoRequest(_ text: String) -> Data {
    var request = Echo_EchoRequest()
    request.text = text
    var data = try! request.serializedData()
    // Add the gRPC prefix with the compression byte and the 4 length bytes.
    for i in 0..<4 {
      data.insert(UInt8((data.count >> (i * 8)) & 0xFF), at: 0)
    }
    data.insert(UInt8(0), at: 0)
    return data
  }

  private func gRPCWebOKTrailers() -> Data {
    var data = "grpc-status: 0\r\ngrpc-message: OK".data(using: .utf8)!
    // Add the gRPC prefix with the compression byte and the 4 length bytes.
    for i in 0..<4 {
      data.insert(UInt8((data.count >> (i * 8)) & 0xFF), at: 0)
    }
    data.insert(UInt8(0x80), at: 0)
    return data
  }

  private func sendOverHTTP1(rpcMethod: String, message: String, handler: @escaping (Data?, Error?) -> Void) {
    let serverURL = URL(string: "http://localhost:5050/echo.Echo/\(rpcMethod)")!
    var request = URLRequest(url: serverURL)
    request.httpMethod = "POST"
    request.setValue("application/grpc-web-text", forHTTPHeaderField: "content-type")

    request.httpBody = gRPCEncodedEchoRequest(message).base64EncodedData()

    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { (data, response, error) in
      handler(data, error)
      sem.signal()
    }.resume()
    _ = sem.wait()
  }
}

extension NIOServerWebTests {
  func testUnary() {
    let message = "hello, world!"
    let expectedData = gRPCEncodedEchoRequest("Swift echo get: \(message)") + gRPCWebOKTrailers()
    let expectedResponse = expectedData.base64EncodedString()

    let completionHandlerExpectation = expectation(description: "completion handler called")

    sendOverHTTP1(rpcMethod: "Get", message: message) { data, error in
      XCTAssertNil(error)
      if let data = data {
        XCTAssertEqual(String(data: data, encoding: .utf8), expectedResponse)
        completionHandlerExpectation.fulfill()
      }
    }

    waitForExpectations(timeout: defaultTimeout)
  }

  func testUnaryLotsOfRequests() {
    // Sending that many requests at once can sometimes trip things up, it seems.
    let clockStart = clock()
    let numberOfRequests = 2_000
    let completionHandlerExpectation = expectation(description: "completion handler called")
#if os(macOS)
    // Linux version of Swift doesn't have this API yet.
    // Implemented in https://github.com/apple/swift-corelibs-xctest/pull/228 but not yet
    // released.
    completionHandlerExpectation.expectedFulfillmentCount = numberOfRequests
#endif
    for i in 0..<numberOfRequests {
      let message = "foo \(i)"
      let expectedData = gRPCEncodedEchoRequest("Swift echo get: \(message)") + gRPCWebOKTrailers()
      let expectedResponse = expectedData.base64EncodedString()
      sendOverHTTP1(rpcMethod: "Get", message: message) { data, error in
        XCTAssertNil(error)
        if let data = data {
          XCTAssertEqual(String(data: data, encoding: .utf8), expectedResponse)
          completionHandlerExpectation.fulfill()
        }
      }
    }
    waitForExpectations(timeout: 10)
    print("total time for \(numberOfRequests) requests: \(Double(clock() - clockStart) / Double(CLOCKS_PER_SEC))")
  }

  func testServerStreaming() {
    let message = "foo bar baz"


    var expectedData = Data()
    var index = 0
    message.split(separator: " ").forEach { (component) in
      expectedData.append(gRPCEncodedEchoRequest("Swift echo expand (\(index)): \(component)"))
      index += 1
    }
    expectedData.append(gRPCWebOKTrailers())
    let expectedResponse = expectedData.base64EncodedString()
    let completionHandlerExpectation = expectation(description: "completion handler called")

    sendOverHTTP1(rpcMethod: "Expand", message: message) { data, error in
      XCTAssertNil(error)
      if let data = data {
        XCTAssertEqual(String(data: data, encoding: .utf8), expectedResponse)
        completionHandlerExpectation.fulfill()
      }
    }

    waitForExpectations(timeout: defaultTimeout)
  }
}
