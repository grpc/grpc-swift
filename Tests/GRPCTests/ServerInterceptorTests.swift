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
import HelloWorldModel
import NIO
import NIOHTTP1
import SwiftProtobuf
import XCTest

class ServerInterceptorTests: GRPCTestCase {
  private var channel: EmbeddedChannel!

  override func setUp() {
    super.setUp()
    self.channel = EmbeddedChannel()
  }

  private func makeRecorder() -> RecordingServerInterceptor<Echo_EchoRequest, Echo_EchoResponse> {
    return .init()
  }

  private func echoProvider(
    interceptedBy interceptor: ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>
  ) -> EchoProvider {
    return EchoProvider(interceptors: EchoInterceptorFactory(interceptor: interceptor))
  }

  private func makeHandlerContext(for path: String) -> CallHandlerContext {
    return CallHandlerContext(
      errorDelegate: nil,
      logger: self.serverLogger,
      encoding: .disabled,
      eventLoop: self.channel.eventLoop,
      path: path,
      responseWriter: NoOpResponseWriter(),
      allocator: ByteBufferAllocator()
    )
  }

  // This is only useful for the type inference.
  private func request(
    _ request: GRPCServerRequestPart<Echo_EchoRequest>
  ) -> GRPCServerRequestPart<Echo_EchoRequest> {
    return request
  }

  private func handleMethod(
    _ method: Substring,
    using provider: CallHandlerProvider
  ) -> GRPCCallHandler? {
    let path = "/\(provider.serviceName)/\(method)"
    let context = self.makeHandlerContext(for: path)
    return provider.handleMethod(method, callHandlerContext: context)
  }

  fileprivate typealias ResponsePart = GRPCServerResponsePart<Echo_EchoResponse>

  func testPassThroughInterceptor() throws {
    let recorder = self.makeRecorder()
    let provider = self.echoProvider(interceptedBy: recorder)

    let handler = try assertNotNil(self.handleMethod("Get", using: provider))
    assertThat(try self.channel.pipeline.addHandlers([Codec(), handler]).wait(), .doesNotThrow())

    // Send requests.
    assertThat(try self.channel.writeInbound(self.request(.metadata([:]))), .doesNotThrow())
    assertThat(
      try self.channel.writeInbound(self.request(.message(.with { $0.text = "" }))),
      .doesNotThrow()
    )
    assertThat(try self.channel.writeInbound(self.request(.end)), .doesNotThrow())

    // Expect responses.
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.metadata()))
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.message()))
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.end()))

    // We expect 2 request parts: the provider responds before it sees end, that's fine.
    assertThat(recorder.requestParts, .hasCount(2))
    assertThat(recorder.requestParts[0], .is(.metadata()))
    assertThat(recorder.requestParts[1], .is(.message()))

    assertThat(recorder.responseParts, .hasCount(3))
    assertThat(recorder.responseParts[0], .is(.metadata()))
    assertThat(recorder.responseParts[1], .is(.message()))
    assertThat(recorder.responseParts[2], .is(.end(status: .is(.ok))))
  }

  func _testExtraRequestPartsAreIgnored(
    part: ExtraRequestPartEmitter.Part,
    callType: GRPCCallType
  ) throws {
    let interceptor = ExtraRequestPartEmitter(repeat: part, times: 3)
    let provider = self.echoProvider(interceptedBy: interceptor)

    let method: Substring

    switch callType {
    case .unary:
      method = "Get"
    case .clientStreaming:
      method = "Collect"
    case .serverStreaming:
      method = "Expand"
    case .bidirectionalStreaming:
      method = "Update"
    }

    let handler = try assertNotNil(self.handleMethod(method, using: provider))
    assertThat(try self.channel.pipeline.addHandlers([Codec(), handler]).wait(), .doesNotThrow())

    // Send the requests.
    assertThat(try self.channel.writeInbound(self.request(.metadata([:]))), .doesNotThrow())
    assertThat(try self.channel.writeInbound(self.request(.message(.init()))), .doesNotThrow())
    assertThat(try self.channel.writeInbound(self.request(.end)), .doesNotThrow())

    // Expect the responses.
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.metadata()))
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.message()))
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.end()))
    // No more response parts.
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .is(.nil()))
  }

  func testExtraRequestMetadataIsIgnoredForUnary() throws {
    try self._testExtraRequestPartsAreIgnored(part: .metadata, callType: .unary)
  }

  func testExtraRequestMessageIsIgnoredForUnary() throws {
    try self._testExtraRequestPartsAreIgnored(part: .message, callType: .unary)
  }

  func testExtraRequestEndIsIgnoredForUnary() throws {
    try self._testExtraRequestPartsAreIgnored(part: .end, callType: .unary)
  }

  func testExtraRequestMetadataIsIgnoredForClientStreaming() throws {
    try self._testExtraRequestPartsAreIgnored(part: .metadata, callType: .clientStreaming)
  }

  func testExtraRequestEndIsIgnoredForClientStreaming() throws {
    try self._testExtraRequestPartsAreIgnored(part: .end, callType: .clientStreaming)
  }

  func testExtraRequestMetadataIsIgnoredForServerStreaming() throws {
    try self._testExtraRequestPartsAreIgnored(part: .metadata, callType: .serverStreaming)
  }

  func testExtraRequestMessageIsIgnoredForServerStreaming() throws {
    try self._testExtraRequestPartsAreIgnored(part: .message, callType: .serverStreaming)
  }

  func testExtraRequestEndIsIgnoredForServerStreaming() throws {
    try self._testExtraRequestPartsAreIgnored(part: .end, callType: .serverStreaming)
  }

  func testExtraRequestMetadataIsIgnoredForBidirectionalStreaming() throws {
    try self._testExtraRequestPartsAreIgnored(part: .metadata, callType: .bidirectionalStreaming)
  }

  func testExtraRequestEndIsIgnoredForBidirectionalStreaming() throws {
    try self._testExtraRequestPartsAreIgnored(part: .end, callType: .bidirectionalStreaming)
  }

  func testUnaryFromInterceptor() throws {
    let provider = EchoFromInterceptor()
    let handler = try assertNotNil(self.handleMethod("Get", using: provider))
    assertThat(try self.channel.pipeline.addHandlers([Codec(), handler]).wait(), .doesNotThrow())

    // Send the requests.
    assertThat(try self.channel.writeInbound(self.request(.metadata([:]))), .doesNotThrow())
    assertThat(
      try self.channel.writeInbound(self.request(.message(.init(text: "foo")))),
      .doesNotThrow()
    )
    assertThat(try self.channel.writeInbound(self.request(.end)), .doesNotThrow())

    // Get the responses.
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.metadata()))
    assertThat(
      try self.channel.readOutbound(as: ResponsePart.self),
      .notNil(.message(.equalTo(.with { $0.text = "echo: foo" })))
    )
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.end()))
  }

  func testClientStreamingFromInterceptor() throws {
    let provider = EchoFromInterceptor()
    let handler = try assertNotNil(self.handleMethod("Collect", using: provider))
    assertThat(try self.channel.pipeline.addHandlers([Codec(), handler]).wait(), .doesNotThrow())

    // Send the requests.
    assertThat(try self.channel.writeInbound(self.request(.metadata([:]))), .doesNotThrow())
    for text in ["a", "b", "c"] {
      let message = self.request(.message(.init(text: text)))
      assertThat(try self.channel.writeInbound(message), .doesNotThrow())
    }
    assertThat(try self.channel.writeInbound(self.request(.end)), .doesNotThrow())

    // Receive responses.
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.metadata()))
    assertThat(
      try self.channel.readOutbound(as: ResponsePart.self),
      .notNil(.message(.equalTo(.with { $0.text = "echo: a b c" })))
    )
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.end()))
  }

  func testServerStreamingFromInterceptor() throws {
    let provider = EchoFromInterceptor()
    let handler = try assertNotNil(self.handleMethod("Expand", using: provider))
    assertThat(try self.channel.pipeline.addHandlers([Codec(), handler]).wait(), .doesNotThrow())

    // Send the requests.
    assertThat(try self.channel.writeInbound(self.request(.metadata([:]))), .doesNotThrow())
    assertThat(
      try self.channel.writeInbound(self.request(.message(.with { $0.text = "a b c" }))),
      .doesNotThrow()
    )
    assertThat(try self.channel.writeInbound(self.request(.end)), .doesNotThrow())

    // Receive responses.
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.metadata()))
    for text in ["a", "b", "c"] {
      let expected = Echo_EchoResponse(text: "echo: " + text)
      assertThat(
        try self.channel.readOutbound(as: ResponsePart.self),
        .notNil(.message(.equalTo(expected)))
      )
    }
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.end()))
  }

  func testBidirectionalStreamingFromInterceptor() throws {
    let provider = EchoFromInterceptor()
    let handler = try assertNotNil(self.handleMethod("Update", using: provider))
    assertThat(try self.channel.pipeline.addHandlers([Codec(), handler]).wait(), .doesNotThrow())

    // Send the requests.
    assertThat(try self.channel.writeInbound(self.request(.metadata([:]))), .doesNotThrow())
    for text in ["a", "b", "c"] {
      assertThat(
        try self.channel.writeInbound(self.request(.message(.init(text: text)))),
        .doesNotThrow()
      )
    }
    assertThat(try self.channel.writeInbound(self.request(.end)), .doesNotThrow())

    // Receive responses.
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.metadata()))
    for text in ["a", "b", "c"] {
      let expected = Echo_EchoResponse(text: "echo: " + text)
      assertThat(
        try self.channel.readOutbound(as: ResponsePart.self),
        .notNil(.message(.equalTo(expected)))
      )
    }
    assertThat(try self.channel.readOutbound(as: ResponsePart.self), .notNil(.end()))
  }
}

class EchoInterceptorFactory: Echo_EchoServerInterceptorFactoryProtocol {
  private let interceptor: ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>

  init(interceptor: ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>) {
    self.interceptor = interceptor
  }

  func makeGetInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [self.interceptor]
  }

  func makeExpandInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [self.interceptor]
  }

  func makeCollectInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [self.interceptor]
  }

  func makeUpdateInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [self.interceptor]
  }
}

class ExtraRequestPartEmitter: ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse> {
  enum Part {
    case metadata
    case message
    case end
  }

  private let part: Part
  private let count: Int

  init(repeat part: Part, times count: Int) {
    self.part = part
    self.count = count
  }

  override func receive(
    _ part: GRPCServerRequestPart<Echo_EchoRequest>,
    context: ServerInterceptorContext<Echo_EchoRequest, Echo_EchoResponse>
  ) {
    let count: Int

    switch (self.part, part) {
    case (.metadata, .metadata),
         (.message, .message),
         (.end, .end):
      count = self.count
    default:
      count = 1
    }

    for _ in 0 ..< count {
      context.receive(part)
    }
  }
}

class EchoFromInterceptor: Echo_EchoProvider {
  var interceptors: Echo_EchoServerInterceptorFactoryProtocol? = Interceptors()

  func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    XCTFail("Unexpected call to \(#function)")
    return context.eventLoop.makeFailedFuture(GRPCStatus.processingError)
  }

  func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    XCTFail("Unexpected call to \(#function)")
    return context.eventLoop.makeFailedFuture(GRPCStatus.processingError)
  }

  func collect(
    context: UnaryResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    XCTFail("Unexpected call to \(#function)")
    return context.eventLoop.makeFailedFuture(GRPCStatus.processingError)
  }

  func update(
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    XCTFail("Unexpected call to \(#function)")
    return context.eventLoop.makeFailedFuture(GRPCStatus.processingError)
  }

  class Interceptors: Echo_EchoServerInterceptorFactoryProtocol {
    func makeGetInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
      return [Interceptor()]
    }

    func makeExpandInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
      return [Interceptor()]
    }

    func makeCollectInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
      return [Interceptor()]
    }

    func makeUpdateInterceptors() -> [ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
      return [Interceptor()]
    }
  }

  // Since all methods use the same request/response types, we can use a single interceptor to
  // respond to all of them.
  class Interceptor: ServerInterceptor<Echo_EchoRequest, Echo_EchoResponse> {
    private var collectedRequests: [Echo_EchoRequest] = []

    override func receive(
      _ part: GRPCServerRequestPart<Echo_EchoRequest>,
      context: ServerInterceptorContext<Echo_EchoRequest, Echo_EchoResponse>
    ) {
      switch part {
      case .metadata:
        context.send(.metadata([:]), promise: nil)

      case let .message(request):
        if context.path.hasSuffix("Get") {
          // Unary, just reply.
          let response = Echo_EchoResponse.with {
            $0.text = "echo: \(request.text)"
          }
          context.send(.message(response, .init(compress: false, flush: false)), promise: nil)
        } else if context.path.hasSuffix("Expand") {
          // Server streaming.
          let parts = request.text.split(separator: " ")
          let metadata = MessageMetadata(compress: false, flush: false)
          for part in parts {
            context.send(.message(.with { $0.text = "echo: \(part)" }, metadata), promise: nil)
          }
        } else if context.path.hasSuffix("Collect") {
          // Client streaming, store the requests, reply on '.end'
          self.collectedRequests.append(request)
        } else if context.path.hasSuffix("Update") {
          // Bidirectional streaming.
          let response = Echo_EchoResponse.with {
            $0.text = "echo: \(request.text)"
          }
          let metadata = MessageMetadata(compress: false, flush: true)
          context.send(.message(response, metadata), promise: nil)
        } else {
          XCTFail("Unexpected path '\(context.path)'")
        }

      case .end:
        if !self.collectedRequests.isEmpty {
          let response = Echo_EchoResponse.with {
            $0.text = "echo: " + self.collectedRequests.map { $0.text }.joined(separator: " ")
          }
          context.send(.message(response, .init(compress: false, flush: false)), promise: nil)
        }

        context.send(.end(.ok, [:]), promise: nil)
      }
    }
  }
}

// Avoid having to serialize/deserialize messages in test cases.
private class Codec: ChannelDuplexHandler {
  typealias InboundIn = GRPCServerRequestPart<Echo_EchoRequest>
  typealias InboundOut = GRPCServerRequestPart<ByteBuffer>

  typealias OutboundIn = GRPCServerResponsePart<ByteBuffer>
  typealias OutboundOut = GRPCServerResponsePart<Echo_EchoResponse>

  private let serializer = ProtobufSerializer<Echo_EchoRequest>()
  private let deserializer = ProtobufDeserializer<Echo_EchoResponse>()

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case let .metadata(headers):
      context.fireChannelRead(self.wrapInboundOut(.metadata(headers)))

    case let .message(message):
      let serialized = try! self.serializer.serialize(message, allocator: context.channel.allocator)
      context.fireChannelRead(self.wrapInboundOut(.message(serialized)))

    case .end:
      context.fireChannelRead(self.wrapInboundOut(.end))
    }
  }

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    switch self.unwrapOutboundIn(data) {
    case let .metadata(headers):
      context.write(self.wrapOutboundOut(.metadata(headers)), promise: promise)

    case let .message(message, metadata):
      let deserialzed = try! self.deserializer.deserialize(byteBuffer: message)
      context.write(self.wrapOutboundOut(.message(deserialzed, metadata)), promise: promise)

    case let .end(status, trailers):
      context.write(self.wrapOutboundOut(.end(status, trailers)), promise: promise)
    }
  }
}
