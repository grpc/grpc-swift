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
@testable import GRPC
import NIO
import XCTest

class ClientTransportTests: GRPCTestCase {
  override func setUp() {
    super.setUp()
    self.channel = EmbeddedChannel()
  }

  // MARK: - Setup Helpers

  private func makeDetails(type: GRPCCallType = .unary) -> CallDetails {
    return CallDetails(
      type: type,
      path: "/echo.Echo/Get",
      authority: "localhost",
      scheme: "https",
      options: .init(logger: self.logger)
    )
  }

  private var channel: EmbeddedChannel!
  private var transport: ClientTransport<String, String>!

  private var eventLoop: EventLoop {
    return self.channel.eventLoop
  }

  private func setUpTransport(
    details: CallDetails? = nil,
    interceptors: [ClientInterceptor<String, String>] = [],
    onError: @escaping (Error) -> Void = { _ in },
    onResponsePart: @escaping (GRPCClientResponsePart<String>) -> Void = { _ in }
  ) {
    self.transport = .init(
      details: details ?? self.makeDetails(),
      eventLoop: self.eventLoop,
      interceptors: interceptors,
      serializer: AnySerializer(wrapping: StringSerializer()),
      deserializer: AnyDeserializer(wrapping: StringDeserializer()),
      errorDelegate: nil,
      onError: onError,
      onResponsePart: onResponsePart
    )
  }

  private func configureTransport(additionalHandlers handlers: [ChannelHandler] = []) {
    self.transport.configure {
      var handlers = handlers
      handlers.append(
        GRPCClientReverseCodecHandler(
          serializer: StringSerializer(),
          deserializer: StringDeserializer()
        )
      )
      handlers.append($0)
      return self.channel.pipeline.addHandlers(handlers)
    }
  }

  private func configureTransport(_ body: @escaping (ChannelHandler) -> EventLoopFuture<Void>) {
    self.transport.configure(body)
  }

  private func connect(file: StaticString = #file, line: UInt = #line) throws {
    let address = try assertNoThrow(SocketAddress(unixDomainSocketPath: "/whatever"))
    assertThat(
      try self.channel.connect(to: address).wait(),
      .doesNotThrow(),
      file: file,
      line: line
    )
  }

  private func sendRequest(
    _ part: GRPCClientRequestPart<String>,
    promise: EventLoopPromise<Void>? = nil
  ) {
    self.transport.send(part, promise: promise)
  }

  private func cancel(promise: EventLoopPromise<Void>? = nil) {
    self.transport.cancel(promise: promise)
  }

  private func sendResponse(
    _ part: _GRPCClientResponsePart<String>,
    file: StaticString = #file,
    line: UInt = #line
  ) throws {
    assertThat(try self.channel.writeInbound(part), .doesNotThrow(), file: file, line: line)
  }
}

// MARK: - Tests

extension ClientTransportTests {
  func testUnaryFlow() throws {
    let recorder = WriteRecorder<_GRPCClientRequestPart<String>>()
    let recorderInterceptor = RecordingInterceptor<String, String>()

    self.setUpTransport(interceptors: [recorderInterceptor])

    // Buffer up some parts.
    self.sendRequest(.metadata([:]))
    self.sendRequest(.message("0", .init(compress: false, flush: false)))

    // Configure the transport and connect. This will unbuffer the parts.
    self.configureTransport(additionalHandlers: [recorder])
    try self.connect()

    // Send the end, this shouldn't require buffering.
    self.sendRequest(.end)

    // We should have recorded 3 parts in the 'Channel' now.
    assertThat(recorder.writes, .hasCount(3))

    // Write some responses.
    try self.sendResponse(.initialMetadata([:]))
    try self.sendResponse(.message(.init("1", compressed: false)))
    try self.sendResponse(.trailingMetadata([:]))
    try self.sendResponse(.status(.ok))

    // The recording interceptor should now have three parts.
    assertThat(recorderInterceptor.responseParts, .hasCount(3))
  }

  func testCancelWhenIdle() throws {
    // Set up the transport, configure it and connect.
    self.setUpTransport(onError: { error in
      assertThat(error, .is(.instanceOf(GRPCError.RPCCancelledByClient.self)))
    })

    // Cancellation should succeed.
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.cancel(promise: promise)
    assertThat(try promise.futureResult.wait(), .doesNotThrow())
  }

  func testCancelWhenAwaitingTransport() throws {
    // Set up the transport, configure it and connect.
    self.setUpTransport(onError: { error in
      assertThat(error, .is(.instanceOf(GRPCError.RPCCancelledByClient.self)))
    })

    // Start configuring the transport.
    let transportActivatedPromise = self.eventLoop.makePromise(of: Void.self)
    // Let's not leak this.
    defer {
      transportActivatedPromise.succeed(())
    }
    self.configureTransport { handler in
      self.channel.pipeline.addHandler(handler).flatMap {
        transportActivatedPromise.futureResult
      }
    }

    // Write a request.
    let p1 = self.eventLoop.makePromise(of: Void.self)
    self.sendRequest(.metadata([:]), promise: p1)

    let p2 = self.eventLoop.makePromise(of: Void.self)
    self.cancel(promise: p2)

    // Cancellation should succeed, and fail the write as a result.
    assertThat(try p2.futureResult.wait(), .doesNotThrow())
    assertThat(
      try p1.futureResult.wait(),
      .throws(.instanceOf(GRPCError.RPCCancelledByClient.self))
    )
  }

  func testCancelWhenActivating() throws {
    // Set up the transport, configure it and connect.
    // We use bidirectional streaming here so that we also flush after writing the metadata.
    self.setUpTransport(
      details: self.makeDetails(type: .bidirectionalStreaming),
      onError: { error in
        assertThat(error, .is(.instanceOf(GRPCError.RPCCancelledByClient.self)))
      }
    )

    // Write a request. This will buffer.
    let writePromise1 = self.eventLoop.makePromise(of: Void.self)
    self.sendRequest(.metadata([:]), promise: writePromise1)

    // Chain a cancel from the first write promise.
    let cancelPromise = self.eventLoop.makePromise(of: Void.self)
    writePromise1.futureResult.whenSuccess {
      self.cancel(promise: cancelPromise)
    }

    // Enqueue a second write.
    let writePromise2 = self.eventLoop.makePromise(of: Void.self)
    self.sendRequest(.message("foo", .init(compress: false, flush: false)), promise: writePromise2)

    // Now we can configure and connect to trigger the unbuffering.
    // We don't actually want to record writes, by the recorder will fulfill promises as we catch
    // them; and we need that.
    self.configureTransport(additionalHandlers: [WriteRecorder<_GRPCClientRequestPart<String>>()])
    try self.connect()

    // The first write should succeed.
    assertThat(try writePromise1.futureResult.wait(), .doesNotThrow())
    // As should the cancellation.
    assertThat(try cancelPromise.futureResult.wait(), .doesNotThrow())
    // The second write should fail: the cancellation happened first.
    assertThat(
      try writePromise2.futureResult.wait(),
      .throws(.instanceOf(GRPCError.RPCCancelledByClient.self))
    )
  }

  func testCancelWhenActive() throws {
    // Set up the transport, configure it and connect. We'll record request parts in the `Channel`.
    let recorder = WriteRecorder<_GRPCClientRequestPart<String>>()
    self.setUpTransport()
    self.configureTransport(additionalHandlers: [recorder])
    try self.connect()

    // We should have an active transport now.
    self.sendRequest(.metadata([:]))
    self.sendRequest(.message("0", .init(compress: false, flush: false)))

    // We should have picked these parts up in the recorder.
    assertThat(recorder.writes, .hasCount(2))

    // Let's cancel now.
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.cancel(promise: promise)

    // Cancellation should succeed.
    assertThat(try promise.futureResult.wait(), .doesNotThrow())
  }

  func testCancelWhenClosing() throws {
    self.setUpTransport()

    // Hold the configuration until we succeed the promise.
    let configuredPromise = self.eventLoop.makePromise(of: Void.self)
    self.configureTransport { handler in
      self.channel.pipeline.addHandler(handler).flatMap {
        configuredPromise.futureResult
      }
    }
  }

  func testCancelWhenClosed() throws {
    // Setup and close immediately.
    self.setUpTransport()
    self.configureTransport()
    try self.connect()
    assertThat(try self.channel.close().wait(), .doesNotThrow())

    // Let's cancel now.
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.cancel(promise: promise)

    // Cancellation should fail, we're already closed.
    assertThat(
      try promise.futureResult.wait(),
      .throws(.instanceOf(GRPCError.AlreadyComplete.self))
    )
  }

  func testErrorWhenActive() throws {
    // Setup the transport, we only expect an error back.
    self.setUpTransport(onError: { error in
      assertThat(error, .is(.instanceOf(DummyError.self)))
    })

    // Configure and activate.
    self.configureTransport()
    try self.connect()

    // Send a request.
    let p1 = self.eventLoop.makePromise(of: Void.self)
    self.sendRequest(.metadata([:]), promise: p1)
    // The transport is for a unary call, so we need to send '.end' to emit a flush and for the
    // promise to be completed.
    self.sendRequest(.end, promise: nil)

    assertThat(try p1.futureResult.wait(), .doesNotThrow())

    // Fire an error back. (We'll see an error on the response handler.)
    self.channel.pipeline.fireErrorCaught(DummyError())

    // Writes should now fail, we're closed.
    let p2 = self.eventLoop.makePromise(of: Void.self)
    self.sendRequest(.end, promise: p2)
    assertThat(try p2.futureResult.wait(), .throws(.instanceOf(GRPCError.AlreadyComplete.self)))
  }

  func testConfigurationFails() throws {
    self.setUpTransport()

    let p1 = self.eventLoop.makePromise(of: Void.self)
    self.sendRequest(.metadata([:]), promise: p1)

    let p2 = self.eventLoop.makePromise(of: Void.self)
    self.sendRequest(.message("0", .init(compress: false, flush: false)), promise: p2)

    // Fail to configure the transport. Our promises should fail.
    self.configureTransport { _ in
      self.eventLoop.makeFailedFuture(DummyError())
    }

    // The promises should fail.
    assertThat(try p1.futureResult.wait(), .throws())
    assertThat(try p2.futureResult.wait(), .throws())

    // Cancellation should also fail because we're already closed.
    let p3 = self.eventLoop.makePromise(of: Void.self)
    self.transport.cancel(promise: p3)
    assertThat(try p3.futureResult.wait(), .throws(.instanceOf(GRPCError.AlreadyComplete.self)))
  }
}

// MARK: - Helper Objects

class WriteRecorder<Write>: ChannelOutboundHandler {
  typealias OutboundIn = Write
  var writes: [Write] = []

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    self.writes.append(self.unwrapOutboundIn(data))
    promise?.succeed(())
  }
}

private struct DummyError: Error {}

internal struct StringSerializer: MessageSerializer {
  typealias Input = String

  func serialize(_ input: String, allocator: ByteBufferAllocator) throws -> ByteBuffer {
    return allocator.buffer(string: input)
  }
}

internal struct StringDeserializer: MessageDeserializer {
  typealias Output = String

  func deserialize(byteBuffer: ByteBuffer) throws -> String {
    var buffer = byteBuffer
    return buffer.readString(length: buffer.readableBytes)!
  }
}

internal struct ThrowingStringSerializer: MessageSerializer {
  typealias Input = String

  func serialize(_ input: String, allocator: ByteBufferAllocator) throws -> ByteBuffer {
    throw DummyError()
  }
}

internal struct ThrowingStringDeserializer: MessageDeserializer {
  typealias Output = String

  func deserialize(byteBuffer: ByteBuffer) throws -> String {
    throw DummyError()
  }
}
