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
#if compiler(>=5.6)
import EchoImplementation
import EchoModel
import GRPC
import HelloWorldModel
import NIOCore
import NIOHPACK
import NIOPosix
import SwiftProtobuf
import XCTest

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
class InterceptorsAsyncTests: GRPCTestCase {
  private var group: EventLoopGroup!
  private var server: Server!
  private var connection: ClientConnection!
  private var echo: Echo_EchoAsyncClient!

  override func setUp() {
    super.setUp()
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.group = group

    let server = try! Server.insecure(group: group)
      .withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "127.0.0.1", port: 0)
      .wait()

    self.server = server

    let connection = ClientConnection.insecure(group: group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "127.0.0.1", port: server.channel.localAddress!.port!)

    self.connection = connection

    self.echo = Echo_EchoAsyncClient(
      channel: connection,
      defaultCallOptions: CallOptions(logger: self.clientLogger),
      interceptors: ReversingInterceptors()
    )
  }

  override func tearDown() {
    if let connection = self.connection {
      XCTAssertNoThrow(try connection.close().wait())
    }
    if let server = self.server {
      XCTAssertNoThrow(try server.close().wait())
    }
    if let group = self.group {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    super.tearDown()
  }

  func testUnaryCall() async throws {
    let get = try await self.echo.get(.with { $0.text = "hello" })
    await assertThat(get, .is(.with { $0.text = "hello :teg ohce tfiwS" }))
  }

  func testMakingUnaryCall() async throws {
    let call = self.echo.makeGetCall(.with { $0.text = "hello" })
    await assertThat(try await call.response, .is(.with { $0.text = "hello :teg ohce tfiwS" }))
  }

  func testClientStreamingSequence() async throws {
    let requests = ["1 2", "3 4"].map { item in
      Echo_EchoRequest.with { $0.text = item }
    }
    let response = try await self.echo.collect(requests, callOptions: .init())

    await assertThat(response, .is(.with { $0.text = "3 4 1 2 :tcelloc ohce tfiwS" }))
  }

  func testClientStreamingAsyncSequence() async throws {
    let stream = AsyncStream<Echo_EchoRequest> { continuation in
      continuation.yield(.with { $0.text = "1 2" })
      continuation.yield(.with { $0.text = "3 4" })
      continuation.finish()
    }
    let response = try await self.echo.collect(stream, callOptions: .init())

    await assertThat(response, .is(.with { $0.text = "3 4 1 2 :tcelloc ohce tfiwS" }))
  }

  func testMakingCallClientStreaming() async throws {
    let call = self.echo.makeCollectCall(callOptions: .init())
    try await call.requestStream.send(.with { $0.text = "1 2" })
    try await call.requestStream.send(.with { $0.text = "3 4" })
    call.requestStream.finish()

    await assertThat(
      try await call.response,
      .is(.with { $0.text = "3 4 1 2 :tcelloc ohce tfiwS" })
    )
  }

  func testServerStreaming() async throws {
    let responses = self.echo.expand(.with { $0.text = "hello" }, callOptions: .init())
    for try await response in responses {
      // Expand splits on spaces, so we only expect one response.
      await assertThat(response, .is(.with { $0.text = "hello :)0( dnapxe ohce tfiwS" }))
    }
  }

  func testMakingCallServerStreaming() async throws {
    let call = self.echo.makeExpandCall(.with { $0.text = "hello" }, callOptions: .init())
    for try await response in call.responseStream {
      // Expand splits on spaces, so we only expect one response.
      await assertThat(response, .is(.with { $0.text = "hello :)0( dnapxe ohce tfiwS" }))
    }
  }

  func testBidirectionalStreaming() async throws {
    let requests = ["1 2", "3 4"].map { item in
      Echo_EchoRequest.with { $0.text = item }
    }
    let responses = self.echo.update(requests, callOptions: .init())

    var count = 0
    for try await response in responses {
      switch count {
      case 0:
        await assertThat(response, .is(.with { $0.text = "1 2 :)0( etadpu ohce tfiwS" }))
      case 1:
        await assertThat(response, .is(.with { $0.text = "3 4 :)1( etadpu ohce tfiwS" }))
      default:
        XCTFail("Got more than 2 responses")
      }
      count += 1
    }
  }

  func testMakingCallBidirectionalStreaming() async throws {
    let call = self.echo.makeUpdateCall(callOptions: .init())
    try await call.requestStream.send(.with { $0.text = "1 2" })
    try await call.requestStream.send(.with { $0.text = "3 4" })
    call.requestStream.finish()

    var count = 0
    for try await response in call.responseStream {
      switch count {
      case 0:
        await assertThat(response, .is(.with { $0.text = "1 2 :)0( etadpu ohce tfiwS" }))
      case 1:
        await assertThat(response, .is(.with { $0.text = "3 4 :)1( etadpu ohce tfiwS" }))
      default:
        XCTFail("Got more than 2 responses")
      }
      count += 1
    }
  }
}

#endif
