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
import NIOCore
import NIOPosix
import NIOTransportServices
import XCTest

@testable import GRPC

#if canImport(Network)
import Network
#endif

class PlatformSupportTests: GRPCTestCase {
  var group: EventLoopGroup!

  override func tearDown() {
    XCTAssertNoThrow(try self.group?.syncShutdownGracefully())
    super.tearDown()
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

  func testRequiresZeroLengthWorkaroundWithMTELG() {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    // No MTELG or individual loop requires the workaround.
    XCTAssertFalse(
      PlatformSupport
        .requiresZeroLengthWriteWorkaround(group: self.group, hasTLS: true)
    )
    XCTAssertFalse(
      PlatformSupport
        .requiresZeroLengthWriteWorkaround(group: self.group, hasTLS: false)
    )
    XCTAssertFalse(
      PlatformSupport
        .requiresZeroLengthWriteWorkaround(group: self.group.next(), hasTLS: true)
    )
    XCTAssertFalse(
      PlatformSupport
        .requiresZeroLengthWriteWorkaround(group: self.group.next(), hasTLS: false)
    )
  }

  func testRequiresZeroLengthWorkaroundWithNetworkFramework() {
    // If we don't have Network.framework we can't test this.
    #if canImport(Network)
    guard #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else { return }
    self.group = NIOTSEventLoopGroup(loopCount: 1)

    // We require the workaround for any of these loops when TLS is not enabled.
    XCTAssertFalse(
      PlatformSupport
        .requiresZeroLengthWriteWorkaround(group: self.group, hasTLS: true)
    )
    XCTAssertTrue(
      PlatformSupport
        .requiresZeroLengthWriteWorkaround(group: self.group, hasTLS: false)
    )
    XCTAssertFalse(
      PlatformSupport
        .requiresZeroLengthWriteWorkaround(group: self.group.next(), hasTLS: true)
    )
    XCTAssertTrue(
      PlatformSupport
        .requiresZeroLengthWriteWorkaround(group: self.group.next(), hasTLS: false)
    )
    #endif
  }

  func testIsTransportServicesGroup() {
    #if canImport(Network)
    guard #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else { return }

    let tsGroup = NIOTSEventLoopGroup(loopCount: 1)
    defer {
      XCTAssertNoThrow(try tsGroup.syncShutdownGracefully())
    }

    XCTAssertTrue(PlatformSupport.isTransportServicesEventLoopGroup(tsGroup))
    XCTAssertTrue(PlatformSupport.isTransportServicesEventLoopGroup(tsGroup.next()))

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    XCTAssertFalse(PlatformSupport.isTransportServicesEventLoopGroup(group))
    XCTAssertFalse(PlatformSupport.isTransportServicesEventLoopGroup(group.next()))

    #endif
  }

  func testIsTLSConfigruationCompatible() {
    #if canImport(Network)
    #if canImport(NIOSSL)
    guard #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else { return }

    let nwConfiguration = GRPCTLSConfiguration.makeClientConfigurationBackedByNetworkFramework()
    let nioSSLConfiguration = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL()

    let tsGroup = NIOTSEventLoopGroup(loopCount: 1)
    defer {
      XCTAssertNoThrow(try tsGroup.syncShutdownGracefully())
    }

    XCTAssertTrue(tsGroup.isCompatible(with: nwConfiguration))
    XCTAssertTrue(tsGroup.isCompatible(with: nioSSLConfiguration))
    XCTAssertTrue(tsGroup.next().isCompatible(with: nwConfiguration))
    XCTAssertTrue(tsGroup.next().isCompatible(with: nioSSLConfiguration))

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    XCTAssertFalse(group.isCompatible(with: nwConfiguration))
    XCTAssertTrue(group.isCompatible(with: nioSSLConfiguration))
    XCTAssertFalse(group.next().isCompatible(with: nwConfiguration))
    XCTAssertTrue(group.next().isCompatible(with: nioSSLConfiguration))
    #endif
    #endif
  }

  func testMakeCompatibleEventLoopGroupForNIOSSL() {
    #if canImport(NIOSSL)
    let configuration = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL()
    let group = PlatformSupport.makeEventLoopGroup(compatibleWith: configuration, loopCount: 1)
    XCTAssertNoThrow(try group.syncShutdownGracefully())
    XCTAssert(group is MultiThreadedEventLoopGroup)
    #endif
  }

  func testMakeCompatibleEventLoopGroupForNetworkFramework() {
    #if canImport(Network)
    guard #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else { return }

    let options = NWProtocolTLS.Options()
    let configuration = GRPCTLSConfiguration.makeClientConfigurationBackedByNetworkFramework(
      options: options
    )

    let group = PlatformSupport.makeEventLoopGroup(compatibleWith: configuration, loopCount: 1)
    XCTAssertNoThrow(try group.syncShutdownGracefully())
    XCTAssert(group is NIOTSEventLoopGroup)

    #endif
  }
}
