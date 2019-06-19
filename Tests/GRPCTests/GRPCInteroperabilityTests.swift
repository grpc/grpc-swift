/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import GRPC
import GRPCInteroperabilityTests
import NIO
import XCTest

/// These are the gRPC interoperability tests running on the NIO client and server.
class GRPCInsecureInteroperabilityTests: XCTestCase {
  var useTLS: Bool { return false }

  var serverEventLoopGroup: EventLoopGroup!
  var server: Server!

  var clientEventLoopGroup: EventLoopGroup!
  var clientConnection: ClientConnection!

  override func setUp() {
    super.setUp()

    self.serverEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.server = try! makeInteroperabilityTestServer(
      host: "localhost",
      port: 0,
      eventLoopGroup: self.serverEventLoopGroup!,
      useTLS: self.useTLS
    ).wait()

    guard let serverPort = self.server.channel.localAddress?.port else {
      XCTFail("Unable to get server port")
      return
    }

    self.clientEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.clientConnection = try! makeInteroperabilityTestClientConnection(
      host: "localhost",
      port: serverPort,
      eventLoopGroup: self.clientEventLoopGroup,
      useTLS: self.useTLS
    )
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.clientConnection.close().wait())
    XCTAssertNoThrow(try self.clientEventLoopGroup.syncShutdownGracefully())
    self.clientConnection = nil
    self.clientEventLoopGroup = nil

    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.serverEventLoopGroup.syncShutdownGracefully())
    self.server = nil
    self.serverEventLoopGroup = nil

    super.tearDown()
  }

  func doRunTest(_ testCase: InteroperabilityTestCase, file: StaticString = #file, line: UInt = #line) {
    // Does the server support the test?
    let implementedFeatures = TestServiceProvider.implementedFeatures
    let missingFeatures = testCase.requiredServerFeatures.subtracting(implementedFeatures)
    guard missingFeatures.isEmpty else {
      print("\(testCase.name) requires features the server does not implement: \(missingFeatures)")
      return
    }

    let test = testCase.makeTest()
    XCTAssertNoThrow(try test.run(using: self.clientConnection), file: file, line: line)
  }

  func testEmptyUnary() {
    self.doRunTest(.emptyUnary)
  }

  func testCacheableUnary() {
    self.doRunTest(.cacheableUnary)
  }

  func testLargeUnary() {
    self.doRunTest(.largeUnary)
  }

  func testClientStreaming() {
    self.doRunTest(.clientStreaming)
  }

  func testServerStreaming() {
    self.doRunTest(.serverStreaming)
  }

  func testPingPong() {
    self.doRunTest(.pingPong)
  }

  func testEmptyStream() {
    self.doRunTest(.emptyStream)
  }

  func testCustomMetadata() {
    self.doRunTest(.customMetadata)
  }

  func testStatusCodeAndMessage() {
    self.doRunTest(.statusCodeAndMessage)
  }

  func testSpecialStatusAndMessage() {
    self.doRunTest(.specialStatusMessage)
  }

  func testUnimplementedMethod() {
    self.doRunTest(.unimplementedMethod)
  }

  func testUnimplementedService() {
    self.doRunTest(.unimplementedService)
  }

  func testCancelAfterBegin() {
    self.doRunTest(.cancelAfterBegin)
  }

  func testCancelAfterFirstResponse() {
    self.doRunTest(.cancelAfterFirstResponse)
  }

  func testTimeoutOnSleepingServer() {
    self.doRunTest(.timeoutOnSleepingServer)
  }
}

class GRPCSecureInteroperabilityTests: GRPCInsecureInteroperabilityTests {
  override var useTLS: Bool { return true }
}
