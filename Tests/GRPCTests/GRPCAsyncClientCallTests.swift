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
#if compiler(>=5.5)

import EchoImplementation
import EchoModel
@testable import GRPC
import NIOHPACK
import NIOPosix
import XCTest

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
class GRPCAsyncClientCallTests: GRPCTestCase {
  private var group: MultiThreadedEventLoopGroup?
  private var server: Server?
  private var channel: ClientConnection?

  private static let OKInitialMetadata = HPACKHeaders([
    (":status", "200"),
    ("content-type", "application/grpc"),
  ])

  private static let OKTrailingMetadata = HPACKHeaders([
    ("grpc-status", "0"),
  ])

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
      request: .with { $0.text = "holt" },
      callOptions: .init()
    )

    await assertThat(try await get.initialMetadata, .is(.equalTo(Self.OKInitialMetadata)))
    await assertThat(try await get.response, .doesNotThrow())
    await assertThat(try await get.trailingMetadata, .is(.equalTo(Self.OKTrailingMetadata)))
    await assertThat(await get.status, .hasCode(.ok))
    print(try await get.trailingMetadata)
  } }

  func testAsyncClientStreamingCall() throws { XCTAsyncTest {
    let channel = try self.setUpServerAndChannel()
    let collect: GRPCAsyncClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse> = channel
      .makeAsyncClientStreamingCall(
        path: "/echo.Echo/Collect",
        callOptions: .init()
      )

    for word in ["boyle", "jeffers", "holt"] {
      try await collect.requestStream.send(.with { $0.text = word })
    }
    try await collect.requestStream.finish()

    await assertThat(try await collect.initialMetadata, .is(.equalTo(Self.OKInitialMetadata)))
    await assertThat(try await collect.response, .doesNotThrow())
    await assertThat(try await collect.trailingMetadata, .is(.equalTo(Self.OKTrailingMetadata)))
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

    await assertThat(try await expand.initialMetadata, .is(.equalTo(Self.OKInitialMetadata)))

    let numResponses = try await expand.responseStream.map { _ in 1 }.reduce(0, +)

    await assertThat(numResponses, .is(.equalTo(3)))
    await assertThat(try await expand.trailingMetadata, .is(.equalTo(Self.OKTrailingMetadata)))
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
      try await update.requestStream.send(.with { $0.text = word })
    }
    try await update.requestStream.finish()

    let numResponses = try await update.responseStream.map { _ in 1 }.reduce(0, +)

    await assertThat(numResponses, .is(.equalTo(3)))
    await assertThat(try await update.trailingMetadata, .is(.equalTo(Self.OKTrailingMetadata)))
    await assertThat(await update.status, .hasCode(.ok))
  } }

  func testAsyncBidirectionalStreamingCall_InterleavedRequestsAndResponses() throws { XCTAsyncTest {
    let channel = try self.setUpServerAndChannel()
    let update: GRPCAsyncBidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse> = channel
      .makeAsyncBidirectionalStreamingCall(
        path: "/echo.Echo/Update",
        callOptions: .init()
      )

    await assertThat(try await update.initialMetadata, .is(.equalTo(Self.OKInitialMetadata)))

    var responseStreamIterator = update.responseStream.makeAsyncIterator()
    for word in ["boyle", "jeffers", "holt"] {
      try await update.requestStream.send(.with { $0.text = word })
      await assertThat(try await responseStreamIterator.next(), .is(.notNil()))
    }

    try await update.requestStream.finish()

    await assertThat(try await responseStreamIterator.next(), .is(.nil()))

    await assertThat(try await update.trailingMetadata, .is(.equalTo(Self.OKTrailingMetadata)))
    await assertThat(await update.status, .hasCode(.ok))
  } }

  func testAsyncBidirectionalStreamingCall_ConcurrentTasks() throws { XCTAsyncTest {
    let channel = try self.setUpServerAndChannel()
    let update: GRPCAsyncBidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse> = channel
      .makeAsyncBidirectionalStreamingCall(
        path: "/echo.Echo/Update",
        callOptions: .init()
      )

    await assertThat(try await update.initialMetadata, .is(.equalTo(Self.OKInitialMetadata)))

    let counter = RequestResponseCounter()

    // Send the requests and get responses in separate concurrent tasks and await the group.
    _ = await withThrowingTaskGroup(of: Void.self) { taskGroup in
      // Send requests, then end, in a task.
      taskGroup.addTask {
        for word in ["boyle", "jeffers", "holt"] {
          try await update.requestStream.send(.with { $0.text = word })
          await counter.incrementRequests()
        }
        try await update.requestStream.finish()
      }
      // Get responses in a separate task.
      taskGroup.addTask {
        for try await _ in update.responseStream {
          await counter.incrementResponses()
        }
      }
    }

    await assertThat(await counter.numRequests, .is(.equalTo(3)))
    await assertThat(await counter.numResponses, .is(.equalTo(3)))
    await assertThat(try await update.trailingMetadata, .is(.equalTo(Self.OKTrailingMetadata)))
    await assertThat(await update.status, .hasCode(.ok))
  } }
}

// Workaround https://bugs.swift.org/browse/SR-15070 (compiler crashes when defining a class/actor
// in an async context).
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
fileprivate actor RequestResponseCounter {
  var numResponses = 0
  var numRequests = 0

  func incrementResponses() async {
    self.numResponses += 1
  }

  func incrementRequests() async {
    self.numRequests += 1
  }
}

#endif
