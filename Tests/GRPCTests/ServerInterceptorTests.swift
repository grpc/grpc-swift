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

extension GRPCServerHandlerProtocol {
  fileprivate func receiveRequest(_ request: Echo_EchoRequest) {
    let serializer = ProtobufSerializer<Echo_EchoRequest>()
    do {
      let buffer = try serializer.serialize(request, allocator: ByteBufferAllocator())
      self.receiveMessage(buffer)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}

class ServerInterceptorTests: GRPCTestCase {
  private let eventLoop = EmbeddedEventLoop()
  private let recorder = ResponseRecorder()

  private func makeRecordingInterceptor()
    -> RecordingServerInterceptor<Echo_EchoRequest, Echo_EchoResponse> {
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
      eventLoop: self.eventLoop,
      path: path,
      responseWriter: self.recorder,
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
  ) -> GRPCServerHandlerProtocol? {
    let path = "/\(provider.serviceName)/\(method)"
    let context = self.makeHandlerContext(for: path)
    return provider.handle(method: method, context: context)
  }

  fileprivate typealias ResponsePart = GRPCServerResponsePart<Echo_EchoResponse>

  func testPassThroughInterceptor() throws {
    let recordingInterceptor = self.makeRecordingInterceptor()
    let provider = self.echoProvider(interceptedBy: recordingInterceptor)

    let handler = try assertNotNil(self.handleMethod("Get", using: provider))

    // Send requests.
    handler.receiveMetadata([:])
    handler.receiveRequest(.with { $0.text = "" })
    handler.receiveEnd()

    // Expect responses.
    assertThat(self.recorder.metadata, .is(.notNil()))
    assertThat(self.recorder.messages.count, .is(1))
    assertThat(self.recorder.status, .is(.notNil()))

    // We expect 2 request parts: the provider responds before it sees end, that's fine.
    assertThat(recordingInterceptor.requestParts, .hasCount(2))
    assertThat(recordingInterceptor.requestParts[0], .is(.metadata()))
    assertThat(recordingInterceptor.requestParts[1], .is(.message()))

    assertThat(recordingInterceptor.responseParts, .hasCount(3))
    assertThat(recordingInterceptor.responseParts[0], .is(.metadata()))
    assertThat(recordingInterceptor.responseParts[1], .is(.message()))
    assertThat(recordingInterceptor.responseParts[2], .is(.end(status: .is(.ok))))
  }

  func testUnaryFromInterceptor() throws {
    let provider = EchoFromInterceptor()
    let handler = try assertNotNil(self.handleMethod("Get", using: provider))

    // Send the requests.
    handler.receiveMetadata([:])
    handler.receiveRequest(.with { $0.text = "foo" })
    handler.receiveEnd()

    // Get the responses.
    assertThat(self.recorder.metadata, .is(.notNil()))
    assertThat(self.recorder.messages.count, .is(1))
    assertThat(self.recorder.status, .is(.notNil()))
  }

  func testClientStreamingFromInterceptor() throws {
    let provider = EchoFromInterceptor()
    let handler = try assertNotNil(self.handleMethod("Collect", using: provider))

    // Send the requests.
    handler.receiveMetadata([:])
    for text in ["a", "b", "c"] {
      handler.receiveRequest(.with { $0.text = text })
    }
    handler.receiveEnd()

    // Get the responses.
    assertThat(self.recorder.metadata, .is(.notNil()))
    assertThat(self.recorder.messages.count, .is(1))
    assertThat(self.recorder.status, .is(.notNil()))
  }

  func testServerStreamingFromInterceptor() throws {
    let provider = EchoFromInterceptor()
    let handler = try assertNotNil(self.handleMethod("Expand", using: provider))

    // Send the requests.
    handler.receiveMetadata([:])
    handler.receiveRequest(.with { $0.text = "a b c" })
    handler.receiveEnd()

    // Get the responses.
    assertThat(self.recorder.metadata, .is(.notNil()))
    assertThat(self.recorder.messages.count, .is(3))
    assertThat(self.recorder.status, .is(.notNil()))
  }

  func testBidirectionalStreamingFromInterceptor() throws {
    let provider = EchoFromInterceptor()
    let handler = try assertNotNil(self.handleMethod("Update", using: provider))

    // Send the requests.
    handler.receiveMetadata([:])
    for text in ["a", "b", "c"] {
      handler.receiveRequest(.with { $0.text = text })
    }
    handler.receiveEnd()

    // Get the responses.
    assertThat(self.recorder.metadata, .is(.notNil()))
    assertThat(self.recorder.messages.count, .is(3))
    assertThat(self.recorder.status, .is(.notNil()))
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
