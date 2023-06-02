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
import protocol SwiftProtobuf.Message
import XCTest

final class InterceptedRPCCancellationTests: GRPCTestCase {
  func testCancellationWithinInterceptedRPC() throws {
    // This test validates that when using interceptors to replay an RPC that the lifecycle of
    // the interceptor pipeline is correctly managed. That is, the transport maintains a reference
    // to the pipeline for as long as the call is alive (rather than dropping the reference when
    // the RPC ends).
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    // Interceptor checks that a "magic" header is present.
    let serverInterceptors = EchoServerInterceptors({ MagicRequiredServerInterceptor() })
    let server = try Server.insecure(group: group)
      .withLogger(self.serverLogger)
      .withServiceProviders([EchoProvider(interceptors: serverInterceptors)])
      .bind(host: "127.0.0.1", port: 0)
      .wait()
    defer {
      XCTAssertNoThrow(try server.close().wait())
    }

    let connection = ClientConnection.insecure(group: group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "127.0.0.1", port: server.channel.localAddress!.port!)
    defer {
      XCTAssertNoThrow(try connection.close().wait())
    }

    // Retries an RPC with a "magic" header if it fails with the permission denied status code.
    let clientInterceptors = EchoClientInterceptors {
      return MagicAddingClientInterceptor(channel: connection)
    }

    let echo = Echo_EchoNIOClient(channel: connection, interceptors: clientInterceptors)

    let receivedFirstResponse = connection.eventLoop.makePromise(of: Void.self)
    let update = echo.update { _ in
      receivedFirstResponse.succeed(())
    }

    XCTAssertNoThrow(try update.sendMessage(.with { $0.text = "ping" }).wait())
    // Wait for the pong: it means the second RPC is up and running and the first should have
    // completed.
    XCTAssertNoThrow(try receivedFirstResponse.futureResult.wait())
    XCTAssertNoThrow(try update.cancel().wait())

    let status = try update.status.wait()
    XCTAssertEqual(status.code, .cancelled)
  }
}

final class MagicRequiredServerInterceptor<
  Request: Message,
  Response: Message
>: ServerInterceptor<Request, Response> {
  override func receive(
    _ part: GRPCServerRequestPart<Request>,
    context: ServerInterceptorContext<Request, Response>
  ) {
    switch part {
    case let .metadata(metadata):
      if metadata.contains(name: "magic") {
        context.log.debug("metadata contains magic; accepting rpc")
        context.receive(part)
      } else {
        context.log.debug("metadata does not contains magic; rejecting rpc")
        let status = GRPCStatus(code: .permissionDenied, message: nil)
        context.send(.end(status, [:]), promise: nil)
      }
    case .message, .end:
      context.receive(part)
    }
  }
}

final class MagicAddingClientInterceptor<
  Request: Message,
  Response: Message
>: ClientInterceptor<Request, Response> {
  private let channel: GRPCChannel
  private var requestParts = CircularBuffer<GRPCClientRequestPart<Request>>()
  private var retry: Call<Request, Response>?

  init(channel: GRPCChannel) {
    self.channel = channel
  }

  override func cancel(
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    if let retry = self.retry {
      context.log.debug("cancelling retry RPC")
      retry.cancel(promise: promise)
    } else {
      context.cancel(promise: promise)
    }
  }

  override func send(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    if let retry = self.retry {
      context.log.debug("retrying part \(part)")
      retry.send(part, promise: promise)
    } else {
      switch part {
      case .metadata:
        // Replace the metadata with the magic words.
        self.requestParts.append(.metadata(["magic": "it's real!"]))
      case .message, .end:
        self.requestParts.append(part)
      }
      context.send(part, promise: promise)
    }
  }

  override func receive(
    _ part: GRPCClientResponsePart<Response>,
    context: ClientInterceptorContext<Request, Response>
  ) {
    switch part {
    case .metadata, .message:
      XCTFail("Unexpected response part \(part)")
      context.receive(part)

    case let .end(status, _):
      guard status.code == .permissionDenied else {
        XCTFail("Unexpected status code \(status)")
        context.receive(part)
        return
      }

      XCTAssertNil(self.retry)

      context.log.debug("initial rpc failed, retrying")

      self.retry = self.channel.makeCall(
        path: context.path,
        type: context.type,
        callOptions: CallOptions(logger: context.logger),
        interceptors: []
      )

      self.retry!.invoke(onError: {
        context.log.debug("intercepting error from retried rpc")
        context.errorCaught($0)
      }) { responsePart in
        context.log.debug("intercepting response part from retried rpc")
        context.receive(responsePart)
      }

      while let requestPart = self.requestParts.popFirst() {
        context.log.debug("replaying \(requestPart) on new rpc")
        self.retry!.send(requestPart, promise: nil)
      }
    }
  }
}

// MARK: - GRPC Logger

// Our tests also check the "Source" of a logger is "GRPC". That assertion fails when we log from
// tests so we'll use our internal logger instead.
extension ClientInterceptorContext {
  var log: GRPCLogger {
    return GRPCLogger(wrapping: self.logger)
  }
}

extension ServerInterceptorContext {
  var log: GRPCLogger {
    return GRPCLogger(wrapping: self.logger)
  }
}
