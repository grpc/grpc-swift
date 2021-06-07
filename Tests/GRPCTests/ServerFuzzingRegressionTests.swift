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
import EchoImplementation
import struct Foundation.Data
import struct Foundation.URL
import GRPC
import NIO
import XCTest

final class ServerFuzzingRegressionTests: GRPCTestCase {
  private static let failCasesURL = URL(fileURLWithPath: #file)
    .deletingLastPathComponent() // ServerFuzzingRegressionTests.swift
    .deletingLastPathComponent() // GRPCTests
    .deletingLastPathComponent() // Tests
    .appendingPathComponent("FuzzTesting")
    .appendingPathComponent("FailCases")

  private func runTest(withInput buffer: ByteBuffer) {
    let channel = EmbeddedChannel()
    defer {
      _ = try? channel.finish()
    }

    let configuration = Server.Configuration.default(
      target: .unixDomainSocket("/ignored"),
      eventLoopGroup: channel.eventLoop,
      serviceProviders: [EchoProvider()]
    )

    XCTAssertNoThrow(try channel._configureForServerFuzzing(configuration: configuration))
    // We're okay with errors. Crashes are bad though.
    _ = try? channel.writeInbound(buffer)
    channel.embeddedEventLoop.run()
  }

  private func runTest(withInputNamed name: String) throws {
    let url = ServerFuzzingRegressionTests.failCasesURL.appendingPathComponent(name)
    let data = try Data(contentsOf: url)
    let buffer = ByteBuffer(data: data)
    self.runTest(withInput: buffer)
  }

  func testFuzzCase_debug_4645975625957376() {
    let name = "clusterfuzz-testcase-minimized-grpc-swift-fuzz-debug-4645975625957376"
    XCTAssertNoThrow(try self.runTest(withInputNamed: name))
  }

  func testFuzzCase_release_5413100925878272() {
    let name = "clusterfuzz-testcase-minimized-grpc-swift-fuzz-release-5413100925878272"
    XCTAssertNoThrow(try self.runTest(withInputNamed: name))
  }
}
