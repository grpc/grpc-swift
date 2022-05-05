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
import GRPCInteroperabilityTestsImplementation
import NIOCore
import NIOPosix
import XCTest

/// These are the gRPC interoperability tests running on the NIO client and server.
class GRPCInsecureInteroperabilityTests: GRPCTestCase {
  var useTLS: Bool { return false }

  var serverEventLoopGroup: EventLoopGroup!
  var server: Server!
  var serverPort: Int!

  var clientEventLoopGroup: EventLoopGroup!
  var clientConnection: ClientConnection!

  override func setUp() {
    super.setUp()

    self.serverEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.server = try! makeInteroperabilityTestServer(
      host: "localhost",
      port: 0,
      eventLoopGroup: self.serverEventLoopGroup!,
      useTLS: self.useTLS,
      logger: self.serverLogger
    ).wait()

    guard let serverPort = self.server.channel.localAddress?.port else {
      XCTFail("Unable to get server port")
      return
    }

    self.serverPort = serverPort

    self.clientEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    // This may throw if we shutdown before the channel was ready.
    try? self.clientConnection?.close().wait()
    XCTAssertNoThrow(try self.clientEventLoopGroup.syncShutdownGracefully())
    self.clientConnection = nil
    self.clientEventLoopGroup = nil

    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.serverEventLoopGroup.syncShutdownGracefully())
    self.server = nil
    self.serverPort = nil
    self.serverEventLoopGroup = nil

    super.tearDown()
  }

  private func doRunTest(_ testCase: InteroperabilityTestCase, line: UInt = #line) {
    // Does the server support the test?
    let implementedFeatures = TestServiceProvider.implementedFeatures
    let missingFeatures = testCase.requiredServerFeatures.subtracting(implementedFeatures)
    guard missingFeatures.isEmpty else {
      print("\(testCase.name) requires features the server does not implement: \(missingFeatures)")
      return
    }

    let test = testCase.makeTest()
    let builder = makeInteroperabilityTestClientBuilder(
      group: self.clientEventLoopGroup,
      useTLS: self.useTLS
    ).withBackgroundActivityLogger(self.clientLogger)
    test.configure(builder: builder)
    self.clientConnection = builder.connect(host: "localhost", port: self.serverPort)
    XCTAssertNoThrow(try test.run(using: self.clientConnection), line: line)
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

  func testClientCompressedUnary() {
    self.doRunTest(.clientCompressedUnary)
  }

  func testServerCompressedUnary() {
    self.doRunTest(.serverCompressedUnary)
  }

  func testClientStreaming() {
    self.doRunTest(.clientStreaming)
  }

  func testClientCompressedStreaming() {
    self.doRunTest(.clientCompressedStreaming)
  }

  func testServerStreaming() {
    self.doRunTest(.serverStreaming)
  }

  func testServerCompressedStreaming() {
    self.doRunTest(.serverCompressedStreaming)
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

#if canImport(NIOSSL)
class GRPCSecureInteroperabilityTests: GRPCInsecureInteroperabilityTests {
  override var useTLS: Bool { return true }

  override func testEmptyUnary() {
    super.testEmptyUnary()
  }

  override func testCacheableUnary() {
    super.testCacheableUnary()
  }

  override func testLargeUnary() {
    super.testLargeUnary()
  }

  override func testClientCompressedUnary() {
    super.testClientCompressedUnary()
  }

  override func testServerCompressedUnary() {
    super.testServerCompressedUnary()
  }

  override func testClientStreaming() {
    super.testClientStreaming()
  }

  override func testClientCompressedStreaming() {
    super.testClientCompressedStreaming()
  }

  override func testServerStreaming() {
    super.testServerStreaming()
  }

  override func testServerCompressedStreaming() {
    super.testServerCompressedStreaming()
  }

  override func testPingPong() {
    super.testPingPong()
  }

  override func testEmptyStream() {
    super.testEmptyStream()
  }

  override func testCustomMetadata() {
    super.testCustomMetadata()
  }

  override func testStatusCodeAndMessage() {
    super.testStatusCodeAndMessage()
  }

  override func testSpecialStatusAndMessage() {
    super.testSpecialStatusAndMessage()
  }

  override func testUnimplementedMethod() {
    super.testUnimplementedMethod()
  }

  override func testUnimplementedService() {
    super.testUnimplementedService()
  }

  override func testCancelAfterBegin() {
    super.testCancelAfterBegin()
  }

  override func testCancelAfterFirstResponse() {
    super.testCancelAfterFirstResponse()
  }

  override func testTimeoutOnSleepingServer() {
    super.testTimeoutOnSleepingServer()
  }
}
#endif // canImport(NIOSSL)
