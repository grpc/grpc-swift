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
import EchoModel
@testable import GRPC
import NIOCore
import NIOPosix
import XCTest

#if compiler(>=5.5)

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
class GRPCAsyncClientCallTests: GRPCTestCase {
  private var group: MultiThreadedEventLoopGroup?
  private var server: Server?
  private var channel: ClientConnection?

  private func setUpServerAndChannel() throws -> ClientConnection {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.group = group

    let server = try Server.insecure(group: group)
      .withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "127.0.0.1", port: 0)
      .wait()

    self.server = server

    let channel = ClientConnection.insecure(group: group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "127.0.0.1", port: server.channel.localAddress!.port!)

    self.channel = channel

    return channel
  }

  override func tearDown() {
    if let channel = self.channel {
      XCTAssertNoThrow(try channel.close().wait())
    }
    if let server = self.server {
      XCTAssertNoThrow(try server.close().wait())
    }
    if let group = self.group {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    super.tearDown()
  }

  func testAsyncUnaryCall() throws { XCTAsyncTest {
    let channel = try self.setUpServerAndChannel()
    let get: GRPCAsyncUnaryCall<Echo_EchoRequest, Echo_EchoResponse> = channel.makeAsyncUnaryCall(
      path: "/echo.Echo/Get",
      request: .with { $0.text = "get" },
      callOptions: .init()
    )

    await assertThat(try await get.response, .doesNotThrow())
    await assertThat(await get.status, .hasCode(.ok))
  } }

  func testAsyncClientStreamingCall() throws { XCTAsyncTest {
    let channel = try self.setUpServerAndChannel()
    let collect: GRPCAsyncClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse> = channel
      .makeAsyncClientStreamingCall(
        path: "/echo.Echo/Collect",
        callOptions: .init()
      )

    for word in ["boyle", "jeffers", "holt"] {
      try await collect.sendMessage(.with { $0.text = word })
    }
    try await collect.sendEnd()

    await assertThat(try await collect.response, .doesNotThrow())
    await assertThat(await collect.status, .hasCode(.ok))
  } }

  func testAsyncServerStreamingCall() throws { XCTAsyncTest {
    let channel = try self.setUpServerAndChannel()
    let expand: GRPCAsyncServerStreamingCall<Echo_EchoRequest, Echo_EchoResponse> = channel
      .makeAsyncServerStreamingCall(
        path: "/echo.Echo/Expand",
        request: .with { $0.text = "boyle jeffers holt" },
        callOptions: .init()
      )

    var numResponses = 0
    for try await _ in expand.responseStream {
      numResponses += 1
    }
    await assertThat(numResponses, .is(.equalTo(3)))
    await assertThat(await expand.status, .hasCode(.ok))
  } }

  func testAsyncBidirectionalStreamingCall() throws { XCTAsyncTest {
    let channel = try self.setUpServerAndChannel()
    let update: GRPCAsyncBidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse> = channel
      .makeAsyncBidirectionalStreamingCall(
        path: "/echo.Echo/Update",
        callOptions: .init()
      )

    for word in ["boyle", "jeffers", "holt"] {
      try await update.sendMessage(.with { $0.text = word })
    }
    try await update.sendEnd()

    var numResponses = 0
    for try await _ in update.responseStream {
      numResponses += 1
    }
    await assertThat(numResponses, .is(.equalTo(3)))
    await assertThat(await update.status, .hasCode(.ok))
  } }

  func testAsyncBidirectionalStreamingCall_InterleavedRequestsAndResponses() throws { XCTAsyncTest {
    let channel = try self.setUpServerAndChannel()
    let update: GRPCAsyncBidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse> = channel
      .makeAsyncBidirectionalStreamingCall(
        path: "/echo.Echo/Update",
        callOptions: .init()
      )

    // Spin up a task to send the requests with a delay before each one
    Task {
      let delay = TimeAmount.milliseconds(500)
      for word in ["foo", "bar", "baz"] {
        try await Task.sleep(nanoseconds: UInt64(delay.nanoseconds))
        try await update.sendMessage(.with { $0.text = word })
      }
      try await Task.sleep(nanoseconds: UInt64(delay.nanoseconds))
      try await update.sendEnd()
    }

    // ...and then wait on the responses...
    var numResponses = 0
    for try await _ in update.responseStream {
      numResponses += 1
    }

    await assertThat(numResponses, .is(.equalTo(3)))
    await assertThat(await update.status, .hasCode(.ok))
  } }

  func testAsyncBidirectionalStreamingCall_ConcurrentTasks() throws { XCTAsyncTest {
    let channel = try self.setUpServerAndChannel()
    let update: GRPCAsyncBidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse> = channel
      .makeAsyncBidirectionalStreamingCall(
        path: "/echo.Echo/Update",
        callOptions: .init()
      )

    actor TestResults {
      static var numResponses = 0
      static var numRequests = 0
    }

    // Send the requests and get responses in separate concurrent tasks and await the group.
    _ = await withThrowingTaskGroup(of: Void.self) { taskGroup in
      // Send requests in a task, sleeping in between, then send end.
      taskGroup.addTask {
        let delay = TimeAmount.milliseconds(500)
        for word in ["boyle", "jeffers", "holt"] {
          try await Task.sleep(nanoseconds: UInt64(delay.nanoseconds))
          try await update.sendMessage(.with { $0.text = word })
          TestResults.numRequests += 1
        }
        try await Task.sleep(nanoseconds: UInt64(delay.nanoseconds))
        try await update.sendEnd()
      }
      // Get responses in a separate task.
      taskGroup.addTask {
        for try await _ in update.responseStream {
          TestResults.numResponses += 1
        }
      }
    }
    await assertThat(TestResults.numRequests, .is(.equalTo(3)))
    await assertThat(TestResults.numResponses, .is(.equalTo(3)))
    await assertThat(await update.status, .hasCode(.ok))
  } }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public extension XCTestCase {
  /// Cross-platform XCTest support for async-await tests.
  ///
  /// Currently the Linux implementation of XCTest doesn't have async-await support.
  /// Until it does, we make use of this shim which uses a detached `Task` along with
  /// `XCTest.wait(for:timeout:)` to wrap the operation.
  ///
  /// - NOTE: Support for Linux is tracked by https://bugs.swift.org/browse/SR-14403.
  /// - NOTE: Implementation currently in progress: https://github.com/apple/swift-corelibs-xctest/pull/326
  func XCTAsyncTest(
    expectationDescription: String = "Async operation",
    timeout: TimeInterval = 3,
    file: StaticString = #file,
    line: Int = #line,
    operation: @escaping () async throws -> Void
  ) {
    let expectation = self.expectation(description: expectationDescription)
    Task {
      do {
        try await operation()
      } catch {
        XCTFail("Error thrown while executing async function @ \(file):\(line): \(error)")
        Thread.callStackSymbols.forEach { print($0) }
      }
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: timeout)
  }
}

#endif
