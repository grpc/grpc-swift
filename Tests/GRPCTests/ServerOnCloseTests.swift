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
import GRPC
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import XCTest

final class ServerOnCloseTests: GRPCTestCase {
  private var group: EventLoopGroup?
  private var server: Server?
  private var client: ClientConnection?
  private var echo: Echo_EchoNIOClient!

  private var eventLoop: EventLoop {
    return self.group!.next()
  }

  override func tearDown() {
    // Some tests shut down the client/server so we tolerate errors here.
    try? self.client?.close().wait()
    try? self.server?.close().wait()
    XCTAssertNoThrow(try self.group?.syncShutdownGracefully())
    super.tearDown()
  }

  override func setUp() {
    super.setUp()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
  }

  private func setUp(provider: Echo_EchoProvider) throws {
    self.server = try Server.insecure(group: self.group!)
      .withLogger(self.serverLogger)
      .withServiceProviders([provider])
      .bind(host: "localhost", port: 0)
      .wait()

    self.client = ClientConnection.insecure(group: self.group!)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: self.server!.channel.localAddress!.port!)

    self.echo = Echo_EchoNIOClient(
      channel: self.client!,
      defaultCallOptions: CallOptions(logger: self.clientLogger)
    )
  }

  private func startServer(
    echoDelegate: Echo_EchoProvider,
    onClose: @escaping (Result<Void, Error>) -> Void
  ) {
    let provider = OnCloseEchoProvider(delegate: echoDelegate, onClose: onClose)
    XCTAssertNoThrow(try self.setUp(provider: provider))
  }

  private func doTestUnary(
    echoProvider: Echo_EchoProvider,
    completesWithStatus code: GRPCStatus.Code
  ) {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.startServer(echoDelegate: echoProvider) { result in
      promise.completeWith(result)
    }

    let get = self.echo.get(.with { $0.text = "" })
    assertThat(try get.status.wait(), .hasCode(code))
    XCTAssertNoThrow(try promise.futureResult.wait())
  }

  func testUnaryOnCloseHappyPath() throws {
    self.doTestUnary(echoProvider: EchoProvider(), completesWithStatus: .ok)
  }

  func testUnaryOnCloseAfterUserFunctionFails() throws {
    self.doTestUnary(echoProvider: FailingEchoProvider(), completesWithStatus: .internalError)
  }

  func testUnaryOnCloseAfterClientKilled() throws {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.startServer(echoDelegate: NeverResolvingEchoProvider()) { result in
      promise.completeWith(result)
    }

    // We want to wait until the client has sent the request parts before closing. We'll grab the
    // promise for sending end.
    let endSent = self.client!.eventLoop.makePromise(of: Void.self)
    self.echo.interceptors = DelegatingEchoClientInterceptorFactory { part, promise, context in
      switch part {
      case .metadata, .message:
        context.send(part, promise: promise)
      case .end:
        endSent.futureResult.cascade(to: promise)
        context.send(part, promise: endSent)
      }
    }

    _ = self.echo.get(.with { $0.text = "" })
    // Make sure end has been sent before closing the connection.
    XCTAssertNoThrow(try endSent.futureResult.wait())
    XCTAssertNoThrow(try self.client!.close().wait())
    XCTAssertNoThrow(try promise.futureResult.wait())
  }

  private func doTestClientStreaming(
    echoProvider: Echo_EchoProvider,
    completesWithStatus code: GRPCStatus.Code
  ) {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.startServer(echoDelegate: echoProvider) { result in
      promise.completeWith(result)
    }

    let collect = self.echo.collect()
    // We don't know if we'll send successfully or not.
    try? collect.sendEnd().wait()
    assertThat(try collect.status.wait(), .hasCode(code))
    XCTAssertNoThrow(try promise.futureResult.wait())
  }

  func testClientStreamingOnCloseHappyPath() throws {
    self.doTestClientStreaming(echoProvider: EchoProvider(), completesWithStatus: .ok)
  }

  func testClientStreamingOnCloseAfterUserFunctionFails() throws {
    self.doTestClientStreaming(
      echoProvider: FailingEchoProvider(),
      completesWithStatus: .internalError
    )
  }

  func testClientStreamingOnCloseAfterClientKilled() throws {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.startServer(echoDelegate: NeverResolvingEchoProvider()) { error in
      promise.completeWith(error)
    }

    let collect = self.echo.collect()
    XCTAssertNoThrow(try collect.sendMessage(.with { $0.text = "" }).wait())
    XCTAssertNoThrow(try self.client!.close().wait())
    XCTAssertNoThrow(try promise.futureResult.wait())
  }

  private func doTestServerStreaming(
    echoProvider: Echo_EchoProvider,
    completesWithStatus code: GRPCStatus.Code
  ) {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.startServer(echoDelegate: echoProvider) { result in
      promise.completeWith(result)
    }

    let expand = self.echo.expand(.with { $0.text = "1 2 3" }) { _ in /* ignore responses */ }
    assertThat(try expand.status.wait(), .hasCode(code))
    XCTAssertNoThrow(try promise.futureResult.wait())
  }

  func testServerStreamingOnCloseHappyPath() throws {
    self.doTestServerStreaming(echoProvider: EchoProvider(), completesWithStatus: .ok)
  }

  func testServerStreamingOnCloseAfterUserFunctionFails() throws {
    self.doTestServerStreaming(
      echoProvider: FailingEchoProvider(),
      completesWithStatus: .internalError
    )
  }

  func testServerStreamingOnCloseAfterClientKilled() throws {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.startServer(echoDelegate: NeverResolvingEchoProvider()) { result in
      promise.completeWith(result)
    }

    // We want to wait until the client has sent the request parts before closing. We'll grab the
    // promise for sending end.
    let endSent = self.client!.eventLoop.makePromise(of: Void.self)
    self.echo.interceptors = DelegatingEchoClientInterceptorFactory { part, promise, context in
      switch part {
      case .metadata, .message:
        context.send(part, promise: promise)
      case .end:
        endSent.futureResult.cascade(to: promise)
        context.send(part, promise: endSent)
      }
    }

    _ = self.echo.expand(.with { $0.text = "1 2 3" }) { _ in /* ignore responses */ }
    // Make sure end has been sent before closing the connection.
    XCTAssertNoThrow(try endSent.futureResult.wait())
    XCTAssertNoThrow(try self.client!.close().wait())
    XCTAssertNoThrow(try promise.futureResult.wait())
  }

  private func doTestBidirectionalStreaming(
    echoProvider: Echo_EchoProvider,
    completesWithStatus code: GRPCStatus.Code
  ) {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.startServer(echoDelegate: echoProvider) { result in
      promise.completeWith(result)
    }

    let update = self.echo.update { _ in /* ignored */ }
    // We don't know if we'll send successfully or not.
    try? update.sendEnd().wait()
    assertThat(try update.status.wait(), .hasCode(code))
    XCTAssertNoThrow(try promise.futureResult.wait())
  }

  func testBidirectionalStreamingOnCloseHappyPath() throws {
    self.doTestBidirectionalStreaming(echoProvider: EchoProvider(), completesWithStatus: .ok)
  }

  func testBidirectionalStreamingOnCloseAfterUserFunctionFails() throws {
    // TODO: https://github.com/grpc/grpc-swift/issues/1215
    // self.doTestBidirectionalStreaming(
    //   echoProvider: FailingEchoProvider(),
    //   completesWithStatus: .internalError
    // )
  }

  func testBidirectionalStreamingOnCloseAfterClientKilled() throws {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.startServer(echoDelegate: NeverResolvingEchoProvider()) { result in
      promise.completeWith(result)
    }

    let update = self.echo.update { _ in /* ignored */ }
    XCTAssertNoThrow(try update.sendMessage(.with { $0.text = "" }).wait())
    XCTAssertNoThrow(try self.client!.close().wait())
    XCTAssertNoThrow(try promise.futureResult.wait())
  }
}
