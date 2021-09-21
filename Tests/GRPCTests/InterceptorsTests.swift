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
import GRPC
import HelloWorldModel
import NIOCore
import NIOHPACK
import NIOPosix
import SwiftProtobuf
import XCTest

class InterceptorsTests: GRPCTestCase {
  private var group: EventLoopGroup!
  private var server: Server!
  private var connection: ClientConnection!
  private var echo: Echo_EchoClient!

  override func setUp() {
    super.setUp()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    self.server = try! Server.insecure(group: self.group)
      .withServiceProviders([
        EchoProvider(),
        HelloWorldProvider(interceptors: HelloWorldServerInterceptorFactory()),
      ])
      .withLogger(self.serverLogger)
      .bind(host: "localhost", port: 0)
      .wait()

    self.connection = ClientConnection.insecure(group: self.group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: self.server.channel.localAddress!.port!)

    self.echo = Echo_EchoClient(
      channel: self.connection,
      defaultCallOptions: CallOptions(logger: self.clientLogger),
      interceptors: ReversingInterceptors()
    )
  }

  override func tearDown() {
    super.tearDown()
    XCTAssertNoThrow(try self.connection.close().wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
  }

  func testEcho() {
    let get = self.echo.get(.with { $0.text = "hello" })
    assertThat(try get.response.wait(), .is(.with { $0.text = "hello :teg ohce tfiwS" }))
    assertThat(try get.status.wait(), .hasCode(.ok))
  }

  func testCollect() {
    let collect = self.echo.collect()
    collect.sendMessage(.with { $0.text = "1 2" }, promise: nil)
    collect.sendMessage(.with { $0.text = "3 4" }, promise: nil)
    collect.sendEnd(promise: nil)
    assertThat(try collect.response.wait(), .is(.with { $0.text = "3 4 1 2 :tcelloc ohce tfiwS" }))
    assertThat(try collect.status.wait(), .hasCode(.ok))
  }

  func testExpand() {
    let expand = self.echo.expand(.with { $0.text = "hello" }) { response in
      // Expand splits on spaces, so we only expect one response.
      assertThat(response, .is(.with { $0.text = "hello :)0( dnapxe ohce tfiwS" }))
    }
    assertThat(try expand.status.wait(), .hasCode(.ok))
  }

  func testUpdate() {
    let update = self.echo.update { response in
      // We'll just send the one message, so only expect one response.
      assertThat(response, .is(.with { $0.text = "hello :)0( etadpu ohce tfiwS" }))
    }
    update.sendMessage(.with { $0.text = "hello" }, promise: nil)
    update.sendEnd(promise: nil)
    assertThat(try update.status.wait(), .hasCode(.ok))
  }

  func testSayHello() {
    let greeter = Helloworld_GreeterClient(
      channel: self.connection,
      defaultCallOptions: CallOptions(logger: self.clientLogger)
    )

    // Make a call without interceptors.
    let notAuthed = greeter.sayHello(.with { $0.name = "World" })
    assertThat(try notAuthed.response.wait(), .throws())
    assertThat(
      try notAuthed.trailingMetadata.wait(),
      .contains("www-authenticate", ["Magic"])
    )
    assertThat(try notAuthed.status.wait(), .hasCode(.unauthenticated))

    // Add an interceptor factory.
    greeter.interceptors = HelloWorldClientInterceptorFactory(client: greeter)
    // Make sure we break the reference cycle.
    defer {
      greeter.interceptors = nil
    }

    // Try again with the not-really-auth interceptor:
    let hello = greeter.sayHello(.with { $0.name = "PanCakes" })
    assertThat(
      try hello.response.map { $0.message }.wait(),
      .is(.equalTo("Hello, PanCakes, you're authorized!"))
    )
    assertThat(try hello.status.wait(), .hasCode(.ok))
  }
}

// MARK: - Helpers

class HelloWorldProvider: Helloworld_GreeterProvider {
  var interceptors: Helloworld_GreeterServerInterceptorFactoryProtocol?

  init(interceptors: Helloworld_GreeterServerInterceptorFactoryProtocol? = nil) {
    self.interceptors = interceptors
  }

  func sayHello(
    request: Helloworld_HelloRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Helloworld_HelloReply> {
    // Since we're auth'd, the 'userInfo' should have some magic set.
    assertThat(context.userInfo.magic, .is("Magic"))

    let response = Helloworld_HelloReply.with {
      $0.message = "Hello, \(request.name), you're authorized!"
    }
    return context.eventLoop.makeSucceededFuture(response)
  }
}

private class HelloWorldClientInterceptorFactory:
  Helloworld_GreeterClientInterceptorFactoryProtocol {
  var client: Helloworld_GreeterClient

  init(client: Helloworld_GreeterClient) {
    self.client = client
  }

  func makeSayHelloInterceptors(
  ) -> [ClientInterceptor<Helloworld_HelloRequest, Helloworld_HelloReply>] {
    return [NotReallyAuthClientInterceptor(client: self.client)]
  }
}

class RemoteAddressExistsInterceptor<Request, Response>: ServerInterceptor<Request, Response> {
  override func receive(
    _ part: GRPCServerRequestPart<Request>,
    context: ServerInterceptorContext<Request, Response>
  ) {
    XCTAssertNotNil(context.remoteAddress)
    super.receive(part, context: context)
  }
}

class NotReallyAuthServerInterceptor<Request: Message, Response: Message>:
  ServerInterceptor<Request, Response> {
  override func receive(
    _ part: GRPCServerRequestPart<Request>,
    context: ServerInterceptorContext<Request, Response>
  ) {
    switch part {
    case let .metadata(headers):
      if let auth = headers.first(name: "authorization"), auth == "Magic" {
        context.userInfo.magic = auth
        context.receive(part)
      } else {
        // Not auth'd. Fail the RPC.
        let status = GRPCStatus(code: .unauthenticated, message: "You need some magic auth!")
        let trailers = HPACKHeaders([("www-authenticate", "Magic")])
        context.send(.end(status, trailers), promise: nil)
      }

    case .message, .end:
      context.receive(part)
    }
  }
}

class HelloWorldServerInterceptorFactory: Helloworld_GreeterServerInterceptorFactoryProtocol {
  func makeSayHelloInterceptors(
  ) -> [ServerInterceptor<Helloworld_HelloRequest, Helloworld_HelloReply>] {
    return [RemoteAddressExistsInterceptor(), NotReallyAuthServerInterceptor()]
  }
}

class NotReallyAuthClientInterceptor<Request: Message, Response: Message>:
  ClientInterceptor<Request, Response> {
  private let client: Helloworld_GreeterClient

  private enum State {
    // We're trying the call, these are the parts we've sent so far.
    case trying([GRPCClientRequestPart<Request>])
    // We're retrying using this call.
    case retrying(Call<Request, Response>)
  }

  private var state: State = .trying([])

  init(client: Helloworld_GreeterClient) {
    self.client = client
  }

  override func cancel(
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    switch self.state {
    case .trying:
      context.cancel(promise: promise)

    case let .retrying(call):
      call.cancel(promise: promise)
      context.cancel(promise: nil)
    }
  }

  override func send(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    switch self.state {
    case var .trying(parts):
      // Record the part, incase we need to retry.
      parts.append(part)
      self.state = .trying(parts)
      // Forward the request part.
      context.send(part, promise: promise)

    case let .retrying(call):
      // We're retrying, send the part to the retry call.
      call.send(part, promise: promise)
    }
  }

  override func receive(
    _ part: GRPCClientResponsePart<Response>,
    context: ClientInterceptorContext<Request, Response>
  ) {
    switch self.state {
    case var .trying(parts):
      switch part {
      // If 'authentication' fails this is the only part we expect, we can forward everything else.
      case let .end(status, trailers) where status.code == .unauthenticated:
        // We only know how to deal with magic.
        guard trailers.first(name: "www-authenticate") == "Magic" else {
          // We can't handle this, fail.
          context.receive(part)
          return
        }

        // We know how to handle this: make a new call.
        let call: Call<Request, Response> = self.client.channel.makeCall(
          path: context.path,
          type: context.type,
          callOptions: context.options,
          // We could grab interceptors from the client, but we don't need to.
          interceptors: []
        )

        // We're retying the call now.
        self.state = .retrying(call)

        // Invoke the call and redirect responses here.
        call.invoke(onError: context.errorCaught(_:), onResponsePart: context.receive(_:))

        // Parts must contain the metadata as the first item if we got that first response.
        if case var .some(.metadata(metadata)) = parts.first {
          metadata.replaceOrAdd(name: "authorization", value: "Magic")
          parts[0] = .metadata(metadata)
        }

        // Now replay any requests on the retry call.
        for part in parts {
          call.send(part, promise: nil)
        }

      default:
        context.receive(part)
      }

    case .retrying:
      // Ignore anything we receive on the original call.
      ()
    }
  }
}

class EchoReverseInterceptor: ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse> {
  override func send(
    _ part: GRPCClientRequestPart<Echo_EchoRequest>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Echo_EchoRequest, Echo_EchoResponse>
  ) {
    switch part {
    case .message(var request, let metadata):
      request.text = String(request.text.reversed())
      context.send(.message(request, metadata), promise: promise)
    default:
      context.send(part, promise: promise)
    }
  }

  override func receive(
    _ part: GRPCClientResponsePart<Echo_EchoResponse>,
    context: ClientInterceptorContext<Echo_EchoRequest, Echo_EchoResponse>
  ) {
    switch part {
    case var .message(response):
      response.text = String(response.text.reversed())
      context.receive(.message(response))
    default:
      context.receive(part)
    }
  }
}

class ReversingInterceptors: Echo_EchoClientInterceptorFactoryProtocol {
  // This interceptor is stateless, let's just share it.
  private let interceptors = [EchoReverseInterceptor()]

  func makeGetInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.interceptors
  }

  func makeExpandInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.interceptors
  }

  func makeCollectInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.interceptors
  }

  func makeUpdateInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return self.interceptors
  }
}

private enum MagicKey: UserInfo.Key {
  typealias Value = String
}

extension UserInfo {
  fileprivate var magic: MagicKey.Value? {
    get {
      return self[MagicKey.self]
    }
    set {
      self[MagicKey.self] = newValue
    }
  }
}
