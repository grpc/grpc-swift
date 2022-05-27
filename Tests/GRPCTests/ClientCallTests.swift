/*
 * Copyright 2020, gRPC Authors All rights reserved.
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

class ClientCallTests: GRPCTestCase {
  private var group: MultiThreadedEventLoopGroup!
  private var server: Server!
  private var connection: ClientConnection!

  override func setUp() {
    super.setUp()

    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.server = try! Server.insecure(group: self.group)
      .withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "localhost", port: 0)
      .wait()

    let port = self.server.channel.localAddress!.port!
    self.connection = ClientConnection.insecure(group: self.group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: port)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.connection.close().wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())

    super.tearDown()
  }

  private func makeCall(
    path: String,
    type: GRPCCallType
  ) -> Call<Echo_EchoRequest, Echo_EchoResponse> {
    return self.connection.makeCall(path: path, type: type, callOptions: .init(), interceptors: [])
  }

  private func get() -> Call<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeCall(path: "/echo.Echo/Get", type: .unary)
  }

  private func collect() -> Call<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeCall(path: "/echo.Echo/Collect", type: .clientStreaming)
  }

  private func expand() -> Call<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeCall(path: "/echo.Echo/Expand", type: .serverStreaming)
  }

  private func update() -> Call<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeCall(path: "/echo.Echo/Update", type: .bidirectionalStreaming)
  }

  private func makeStatusPromise() -> EventLoopPromise<GRPCStatus> {
    return self.connection.eventLoop.makePromise()
  }

  /// Makes a response part handler which succeeds the promise when receiving the status and fails
  /// it if an error is received.
  private func makeResponsePartHandler<Response>(
    for: Response.Type = Response.self,
    completing promise: EventLoopPromise<GRPCStatus>
  ) -> (GRPCClientResponsePart<Response>) -> Void {
    return { part in
      switch part {
      case .metadata, .message:
        ()
      case let .end(status, _):
        promise.succeed(status)
      }
    }
  }

  // MARK: - Tests

  func testFullyManualUnary() throws {
    let get = self.get()

    let statusPromise = self.makeStatusPromise()
    get.invoke(
      onError: statusPromise.fail(_:),
      onResponsePart: self.makeResponsePartHandler(completing: statusPromise)
    )

    let f1 = get.send(.metadata(get.options.customMetadata))
    let f2 = get.send(.message(.with { $0.text = "get" }, .init(compress: false, flush: false)))
    let f3 = get.send(.end)

    // '.end' will flush, so we can wait on the futures now.
    assertThat(try f1.wait(), .doesNotThrow())
    assertThat(try f2.wait(), .doesNotThrow())
    assertThat(try f3.wait(), .doesNotThrow())

    // Status should be ok.
    assertThat(try statusPromise.futureResult.wait(), .hasCode(.ok))
  }

  func testUnaryCall() {
    let get = self.get()

    let promise = self.makeStatusPromise()
    get.invokeUnaryRequest(
      .with { $0.text = "get" },
      onError: promise.fail(_:),
      onResponsePart: self.makeResponsePartHandler(completing: promise)
    )

    assertThat(try promise.futureResult.wait(), .hasCode(.ok))
  }

  func testClientStreaming() {
    let collect = self.collect()

    let promise = self.makeStatusPromise()
    collect.invokeStreamingRequests(
      onError: promise.fail(_:),
      onResponsePart: self.makeResponsePartHandler(completing: promise)
    )
    collect.send(
      .message(.with { $0.text = "collect" }, .init(compress: false, flush: false)),
      promise: nil
    )
    collect.send(.end, promise: nil)

    assertThat(try promise.futureResult.wait(), .hasCode(.ok))
  }

  func testServerStreaming() {
    let expand = self.expand()

    let promise = self.makeStatusPromise()
    expand.invokeUnaryRequest(
      .with { $0.text = "expand" },
      onError: promise.fail(_:),
      onResponsePart: self.makeResponsePartHandler(completing: promise)
    )

    assertThat(try promise.futureResult.wait(), .hasCode(.ok))
  }

  func testBidirectionalStreaming() {
    let update = self.update()

    let promise = self.makeStatusPromise()
    update.invokeStreamingRequests(
      onError: promise.fail(_:),
      onResponsePart: self.makeResponsePartHandler(completing: promise)
    )
    update.send(
      .message(.with { $0.text = "update" }, .init(compress: false, flush: false)),
      promise: nil
    )
    update.send(.end, promise: nil)

    assertThat(try promise.futureResult.wait(), .hasCode(.ok))
  }

  func testSendBeforeInvoke() throws {
    let get = self.get()
    assertThat(try get.send(.end).wait(), .throws())
  }

  func testCancelBeforeInvoke() throws {
    let get = self.get()
    XCTAssertNoThrow(try get.cancel().wait())
  }

  func testCancelMidRPC() throws {
    let get = self.get()
    let promise = self.makeStatusPromise()
    get.invoke(
      onError: promise.fail(_:),
      onResponsePart: self.makeResponsePartHandler(completing: promise)
    )

    // Cancellation should succeed.
    assertThat(try get.cancel().wait(), .doesNotThrow())

    assertThat(try promise.futureResult.wait(), .hasCode(.cancelled))

    // Cancellation should now fail, we've already cancelled.
    assertThat(try get.cancel().wait(), .throws(.instanceOf(GRPCError.AlreadyComplete.self)))
  }
}
