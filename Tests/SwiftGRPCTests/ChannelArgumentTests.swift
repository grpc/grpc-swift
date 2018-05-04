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
#if SWIFT_PACKAGE
import CgRPC
#endif
import Foundation
@testable import SwiftGRPC
import XCTest

fileprivate class ChannelArgumentTestProvider: Echo_EchoProvider {
  func get(request: Echo_EchoRequest, session: Echo_EchoGetSession) throws -> Echo_EchoResponse {
    // We simply return the user agent we received, which can then be inspected by the test code.
    return Echo_EchoResponse(text: (session as! ServerSessionBase).handler.requestMetadata["user-agent"]!)
  }
  
  func expand(request: Echo_EchoRequest, session: Echo_EchoExpandSession) throws {
    fatalError("not implemented")
  }
  
  func collect(session: Echo_EchoCollectSession) throws {
    fatalError("not implemented")
  }
  
  func update(session: Echo_EchoUpdateSession) throws {
    fatalError("not implemented")
  }
}

class ChannelArgumentTests: BasicEchoTestCase {
  static var allTests: [(String, (ChannelArgumentTests) -> () throws -> Void)] {
    return [
      ("testArgumentKey", testArgumentKey),
      ("testStringArgument", testStringArgument),
      ("testIntegerArgument", testIntegerArgument),
      ("testBoolArgument", testBoolArgument),
      ("testTimeIntervalArgument", testTimeIntervalArgument),
    ]
  }
  
  fileprivate func makeClient(_ arguments: [Channel.Argument]) -> Echo_EchoServiceClient {
    let client = Echo_EchoServiceClient(address: address, secure: false, arguments: arguments)
    client.timeout = defaultTimeout
    return client
  }
  
  override func makeProvider() -> Echo_EchoProvider { return ChannelArgumentTestProvider() }
}

extension ChannelArgumentTests {
  func testArgumentKey() {
    let argument = Channel.Argument.defaultAuthority("default")
    XCTAssertEqual(String(cString: argument.toCArg().wrapped.key), "grpc.default_authority")
  }

  func testStringArgument() {
    let argument = Channel.Argument.primaryUserAgent("Primary/0.1")
    XCTAssertEqual(String(cString: argument.toCArg().wrapped.value.string), "Primary/0.1")
  }

  func testIntegerArgument() {
    let argument = Channel.Argument.http2MaxPingsWithoutData(5)
    XCTAssertEqual(argument.toCArg().wrapped.value.integer, 5)
  }

  func testBoolArgument() {
    let argument = Channel.Argument.keepAlivePermitWithoutCalls(true)
    XCTAssertEqual(argument.toCArg().wrapped.value.integer, 1)
  }

  func testTimeIntervalArgument() {
    let argument = Channel.Argument.keepAliveTime(2.5)
    XCTAssertEqual(argument.toCArg().wrapped.value.integer, 2500) // in ms
  }
}

extension ChannelArgumentTests {
  func testPracticalUse() {
    let client = makeClient([.primaryUserAgent("FOO"), .secondaryUserAgent("BAR")])
    let responseText = try! client.get(Echo_EchoRequest(text: "")).text
    XCTAssertTrue(responseText.hasPrefix("FOO "), "user agent \(responseText) should begin with 'FOO '")
    XCTAssertTrue(responseText.hasSuffix(" BAR"), "user agent \(responseText) should end with ' BAR'")
  }
}
