/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import GRPC
import NIOEmbedded
import XCTest

final class ConfigurationTests: GRPCTestCase {
  private var eventLoop: EmbeddedEventLoop!

  private var clientDefaults: ClientConnection.Configuration {
    return .default(target: .unixDomainSocket("/ignored"), eventLoopGroup: self.eventLoop)
  }

  private var serverDefaults: Server.Configuration {
    return .default(
      target: .unixDomainSocket("/ignored"),
      eventLoopGroup: self.eventLoop,
      serviceProviders: []
    )
  }

  override func setUp() {
    super.setUp()
    self.eventLoop = EmbeddedEventLoop()
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.eventLoop.syncShutdownGracefully())
    super.tearDown()
  }

  private let maxFrameSizeMinimum = (1 << 14)
  private let maxFrameSizeMaximum = (1 << 24) - 1

  private func doTestHTTPMaxFrameSizeIsClamped(for configuration: HasHTTP2Configuration) {
    var configuration = configuration
    configuration.httpMaxFrameSize = 0
    XCTAssertEqual(configuration.httpMaxFrameSize, self.maxFrameSizeMinimum)

    configuration.httpMaxFrameSize = .max
    XCTAssertEqual(configuration.httpMaxFrameSize, self.maxFrameSizeMaximum)

    configuration.httpMaxFrameSize = self.maxFrameSizeMinimum + 1
    XCTAssertEqual(configuration.httpMaxFrameSize, self.maxFrameSizeMinimum + 1)
  }

  func testHTTPMaxFrameSizeIsClampedForClient() {
    self.doTestHTTPMaxFrameSizeIsClamped(for: self.clientDefaults)
  }

  func testHTTPMaxFrameSizeIsClampedForServer() {
    self.doTestHTTPMaxFrameSizeIsClamped(for: self.serverDefaults)
  }

  private let targetWindowSizeMinimum = 1
  private let targetWindowSizeMaximum = Int(Int32.max)

  private func doTestHTTPTargetWindowSizeIsClamped(for configuration: HasHTTP2Configuration) {
    var configuration = configuration
    configuration.httpTargetWindowSize = .min
    XCTAssertEqual(configuration.httpTargetWindowSize, self.targetWindowSizeMinimum)

    configuration.httpTargetWindowSize = .max
    XCTAssertEqual(configuration.httpTargetWindowSize, self.targetWindowSizeMaximum)

    configuration.httpTargetWindowSize = self.targetWindowSizeMinimum + 1
    XCTAssertEqual(configuration.httpTargetWindowSize, self.targetWindowSizeMinimum + 1)
  }

  func testHTTPTargetWindowSizeIsClampedForClient() {
    self.doTestHTTPTargetWindowSizeIsClamped(for: self.clientDefaults)
  }

  func testHTTPTargetWindowSizeIsClampedForServer() {
    self.doTestHTTPTargetWindowSizeIsClamped(for: self.serverDefaults)
  }
}

private protocol HasHTTP2Configuration {
  var httpMaxFrameSize: Int { get set }
  var httpTargetWindowSize: Int { get set }
}

extension ClientConnection.Configuration: HasHTTP2Configuration {}
extension Server.Configuration: HasHTTP2Configuration {}
