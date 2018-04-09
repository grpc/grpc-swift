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

class ChannelArgumentTests: XCTestCase {
  func testArgumentKey() {
    let argument: Channel.Argument = .defaultAuthority("default")
    XCTAssertEqual(String(cString: argument.toCArg().key), "grpc.default_authority")
  }

  func testStringArgument() {
    let argument: Channel.Argument = .primaryUserAgent("Primary/0.1")
    XCTAssertEqual(String(cString: argument.toCArg().value.string), "Primary/0.1")
  }

  func testIntegerArgument() {
    let argument: Channel.Argument = .http2MaxPingsWithoutData(5)
    XCTAssertEqual(argument.toCArg().value.integer, 5)
  }

  func testBoolArgument() {
    let argument: Channel.Argument = .keepAlivePermitWithoutCalls(true)
    XCTAssertEqual(argument.toCArg().value.integer, 1)
  }

  func testTimeIntervalArgument() {
    let argument: Channel.Argument = .keepAliveTime(2.5)
    XCTAssertEqual(argument.toCArg().value.integer, 2500) // in ms
  }
}
