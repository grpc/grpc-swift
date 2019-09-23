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
import NIO
import NIOTransportServices
import XCTest

class PlatformSupportTests: GRPCTestCase {
  var group: EventLoopGroup!

  override func tearDown() {
    XCTAssertNoThrow(try self.group?.syncShutdownGracefully())
  }

  func testMakeEventLoopGroupReturnsMultiThreadedGroupForPosix() {
    self.group = PlatformSupport.makeEventLoopGroup(
      loopCount: 1,
      networkPreference: .userDefined(.posix)
    )

    XCTAssertTrue(self.group is MultiThreadedEventLoopGroup)
  }

  func testMakeEventLoopGroupReturnsNIOTSGroupForNetworkFramework() {
    // If we don't have Network.framework then we can't test this.
    #if canImport(Network)
    guard #available(macOS 10.14, *) else { return }

    self.group = PlatformSupport.makeEventLoopGroup(
      loopCount: 1,
      networkPreference: .userDefined(.networkFramework)
    )

    XCTAssertTrue(self.group is NIOTSEventLoopGroup)
    #endif
  }

  func testMakeClientBootstrapReturnsClientBootstrapForMultiThreadedGroup() {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let bootstrap = PlatformSupport.makeClientBootstrap(group: self.group)
    XCTAssertTrue(bootstrap is ClientBootstrap)
  }

  func testMakeClientBootstrapReturnsClientBootstrapForEventLoop() {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let eventLoop = self.group.next()
    let bootstrap = PlatformSupport.makeClientBootstrap(group: eventLoop)
    XCTAssertTrue(bootstrap is ClientBootstrap)
  }

  func testMakeClientBootstrapReturnsNIOTSConnectionBootstrapForNIOTSGroup() {
    // If we don't have Network.framework then we can't test this.
    #if canImport(Network)
    guard #available(macOS 10.14, *) else { return }

    self.group = NIOTSEventLoopGroup(loopCount: 1)
    let bootstrap = PlatformSupport.makeClientBootstrap(group: self.group)
    XCTAssertTrue(bootstrap is NIOTSConnectionBootstrap)
    #endif
  }

  func testMakeClientBootstrapReturnsNIOTSConnectionBootstrapForQoSEventLoop() {
    // If we don't have Network.framework then we can't test this.
    #if canImport(Network)
    guard #available(macOS 10.14, *) else { return }

    self.group = NIOTSEventLoopGroup(loopCount: 1)

    let eventLoop = self.group.next()
    XCTAssertTrue(eventLoop is QoSEventLoop)

    let bootstrap = PlatformSupport.makeClientBootstrap(group: eventLoop)
    XCTAssertTrue(bootstrap is NIOTSConnectionBootstrap)
    #endif
  }

  func testMakeServerBootstrapReturnsServerBootstrapForMultiThreadedGroup() {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let bootstrap = PlatformSupport.makeServerBootstrap(group: self.group)
    XCTAssertTrue(bootstrap is ServerBootstrap)
  }

  func testMakeServerBootstrapReturnsServerBootstrapForEventLoop() {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    let eventLoop = self.group.next()
    let bootstrap = PlatformSupport.makeServerBootstrap(group: eventLoop)
    XCTAssertTrue(bootstrap is ServerBootstrap)
  }

  func testMakeServerBootstrapReturnsNIOTSListenerBootstrapForNIOTSGroup() {
    // If we don't have Network.framework then we can't test this.
    #if canImport(Network)
    guard #available(macOS 10.14, *) else { return }

    self.group = NIOTSEventLoopGroup(loopCount: 1)
    let bootstrap = PlatformSupport.makeServerBootstrap(group: self.group)
    XCTAssertTrue(bootstrap is NIOTSListenerBootstrap)
    #endif
  }

  func testMakeServerBootstrapReturnsNIOTSListenerBootstrapForQoSEventLoop() {
    // If we don't have Network.framework then we can't test this.
    #if canImport(Network)
    guard #available(macOS 10.14, *) else { return }

    self.group = NIOTSEventLoopGroup(loopCount: 1)

    let eventLoop = self.group.next()
    XCTAssertTrue(eventLoop is QoSEventLoop)

    let bootstrap = PlatformSupport.makeServerBootstrap(group: eventLoop)
    XCTAssertTrue(bootstrap is NIOTSListenerBootstrap)
    #endif
  }
}
