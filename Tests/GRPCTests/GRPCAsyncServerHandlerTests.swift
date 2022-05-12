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

@testable import GRPC
import NIOCore
import NIOEmbedded
import NIOHPACK
import NIOPosix
import XCTest

// MARK: - Tests

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
class AsyncServerHandlerTests: GRPCTestCase {
  private let recorder = AsyncResponseStream()
  private var group: EventLoopGroup!
  private var loop: EventLoop!

  override func setUp() {
    super.setUp()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.loop = self.group.next()
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    super.tearDown()
  }

  func makeCallHandlerContext(
    encoding: ServerMessageEncoding = .disabled
  ) -> CallHandlerContext {
    let closeFuture = self.loop.makeSucceededVoidFuture()

    return CallHandlerContext(
      errorDelegate: nil,
      logger: self.logger,
      encoding: encoding,
      eventLoop: self.loop,
      path: "/ignored",
      remoteAddress: nil,
      responseWriter: self.recorder,
      allocator: ByteBufferAllocator(),
      closeFuture: closeFuture
    )
  }

  private func makeHandler(
    encoding: ServerMessageEncoding = .disabled,
    callType: GRPCCallType = .bidirectionalStreaming,
    observer: @escaping @Sendable (
      GRPCAsyncRequestStream<String>,
      GRPCAsyncResponseStreamWriter<String>,
      GRPCAsyncServerCallContext
    ) async throws -> Void
  ) -> AsyncServerHandler<StringSerializer, StringDeserializer, String, String> {
    return AsyncServerHandler(
      context: self.makeCallHandlerContext(encoding: encoding),
      requestDeserializer: StringDeserializer(),
      responseSerializer: StringSerializer(),
      callType: callType,
      interceptors: [],
      userHandler: observer
    )
  }

  @Sendable
  private static func echo(
    requests: GRPCAsyncRequestStream<String>,
    responseStreamWriter: GRPCAsyncResponseStreamWriter<String>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await message in requests {
      try await responseStreamWriter.send(message)
    }
  }

  @Sendable
  private static func neverReceivesMessage(
    requests: GRPCAsyncRequestStream<String>,
    responseStreamWriter: GRPCAsyncResponseStreamWriter<String>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await message in requests {
      XCTFail("Unexpected message: '\(message)'")
    }
  }

  @Sendable
  private static func neverCalled(
    requests: GRPCAsyncRequestStream<String>,
    responseStreamWriter: GRPCAsyncResponseStreamWriter<String>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    XCTFail("This observer should never be called")
  }

  func testHappyPath() async throws {
    let handler = self.makeHandler(
      observer: Self.echo(requests:responseStreamWriter:context:)
    )
    defer {
      XCTAssertNoThrow(try self.loop.submit { handler.finish() }.wait())
    }

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveMessage(ByteBuffer(string: "1"))
      handler.receiveMessage(ByteBuffer(string: "2"))
      handler.receiveMessage(ByteBuffer(string: "3"))
      handler.receiveEnd()
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertMetadata()
    for expected in ["1", "2", "3"] {
      try await responseStream.next().assertMessage { buffer, metadata in
        XCTAssertEqual(buffer, .init(string: expected))
        XCTAssertFalse(metadata.compress)
      }
    }

    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .ok)
    }
    try await responseStream.next().assertNil()
  }

  func testHappyPathWithCompressionEnabled() async throws {
    let handler = self.makeHandler(
      encoding: .enabled(.init(decompressionLimit: .absolute(.max))),
      observer: Self.echo(requests:responseStreamWriter:context:)
    )
    defer {
      XCTAssertNoThrow(try self.loop.submit { handler.finish() }.wait())
    }

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveMessage(ByteBuffer(string: "1"))
      handler.receiveMessage(ByteBuffer(string: "2"))
      handler.receiveMessage(ByteBuffer(string: "3"))
      handler.receiveEnd()
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertMetadata()
    for expected in ["1", "2", "3"] {
      try await responseStream.next().assertMessage { buffer, metadata in
        XCTAssertEqual(buffer, .init(string: expected))
        XCTAssertTrue(metadata.compress)
      }
    }
    try await responseStream.next().assertStatus()
    try await responseStream.next().assertNil()
  }

  func testHappyPathWithCompressionEnabledButDisabledByCaller() async throws {
    let handler = self.makeHandler(
      encoding: .enabled(.init(decompressionLimit: .absolute(.max)))
    ) { requests, responseStreamWriter, context in
      try await context.response.compressResponses(false)
      return try await Self.echo(
        requests: requests,
        responseStreamWriter: responseStreamWriter,
        context: context
      )
    }
    defer {
      XCTAssertNoThrow(try self.loop.submit { handler.finish() }.wait())
    }

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveMessage(ByteBuffer(string: "1"))
      handler.receiveMessage(ByteBuffer(string: "2"))
      handler.receiveMessage(ByteBuffer(string: "3"))
      handler.receiveEnd()
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertMetadata()
    for expected in ["1", "2", "3"] {
      try await responseStream.next().assertMessage { buffer, metadata in
        XCTAssertEqual(buffer, .init(string: expected))
        XCTAssertFalse(metadata.compress)
      }
    }
    try await responseStream.next().assertStatus()
    try await responseStream.next().assertNil()
  }

  func testResponseHeadersAndTrailersSentFromContext() async throws {
    let handler = self.makeHandler { _, responseStreamWriter, context in
      try await context.response.setHeaders(["pontiac": "bandit"])
      try await responseStreamWriter.send("1")
      try await context.response.setTrailers(["disco": "strangler"])
    }
    defer {
      XCTAssertNoThrow(try self.loop.submit { handler.finish() }.wait())
    }

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveEnd()
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertMetadata { headers in
      XCTAssertEqual(headers, ["pontiac": "bandit"])
    }
    try await responseStream.next().assertMessage()
    try await responseStream.next().assertStatus { _, trailers in
      XCTAssertEqual(trailers, ["disco": "strangler"])
    }
    try await responseStream.next().assertNil()
  }

  func testThrowingDeserializer() async throws {
    let handler = AsyncServerHandler(
      context: self.makeCallHandlerContext(),
      requestDeserializer: ThrowingStringDeserializer(),
      responseSerializer: StringSerializer(),
      callType: .bidirectionalStreaming,
      interceptors: [],
      userHandler: Self.neverReceivesMessage(requests:responseStreamWriter:context:)
    )
    defer {
      XCTAssertNoThrow(try self.loop.submit { handler.finish() }.wait())
    }

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveMessage(ByteBuffer(string: "hello"))
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .internalError)
    }
    try await responseStream.next().assertNil()
  }

  func testThrowingSerializer() async throws {
    let handler = AsyncServerHandler(
      context: self.makeCallHandlerContext(),
      requestDeserializer: StringDeserializer(),
      responseSerializer: ThrowingStringSerializer(),
      callType: .bidirectionalStreaming,
      interceptors: [],
      userHandler: Self.echo(requests:responseStreamWriter:context:)
    )
    defer {
      XCTAssertNoThrow(try self.loop.submit { handler.finish() }.wait())
    }

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveMessage(ByteBuffer(string: "hello"))
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertMetadata()
    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .internalError)
    }
    try await responseStream.next().assertNil()
  }

  func testReceiveMessageBeforeHeaders() async throws {
    let handler = self.makeHandler(
      observer: Self.neverCalled(requests:responseStreamWriter:context:)
    )
    defer {
      XCTAssertNoThrow(try self.loop.submit { handler.finish() }.wait())
    }

    self.loop.execute {
      handler.receiveMessage(ByteBuffer(string: "foo"))
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .internalError)
    }
    try await responseStream.next().assertNil()
  }

  func testReceiveMultipleHeaders() async throws {
    let handler = self.makeHandler(
      observer: Self.neverReceivesMessage(requests:responseStreamWriter:context:)
    )
    defer {
      XCTAssertNoThrow(try self.loop.submit { handler.finish() }.wait())
    }

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveMetadata([:])
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .internalError)
    }
    try await responseStream.next().assertNil()
  }

  func testFinishBeforeStarting() async throws {
    let handler = self.makeHandler(
      observer: Self.neverCalled(requests:responseStreamWriter:context:)
    )

    self.loop.execute {
      handler.finish()
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertStatus()
    try await responseStream.next().assertNil()
  }

  func testFinishAfterHeaders() async throws {
    let handler = self.makeHandler(
      observer: Self.neverReceivesMessage(requests:responseStreamWriter:context:)
    )

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.finish()
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertStatus()
    try await responseStream.next().assertNil()
  }

  func testFinishAfterMessage() async throws {
    let handler = self.makeHandler(observer: Self.echo(requests:responseStreamWriter:context:))

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveMessage(ByteBuffer(string: "hello"))
    }

    // Await the metadata and message so we know the user function is running.
    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertMetadata()
    try await responseStream.next().assertMessage()

    // Finish, i.e. terminate early.
    self.loop.execute {
      handler.finish()
    }

    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .internalError)
    }
    try await responseStream.next().assertNil()
  }

  func testErrorAfterHeaders() async throws {
    let handler = self.makeHandler(observer: Self.echo(requests:responseStreamWriter:context:))

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveError(CancellationError())
    }

    // We don't send a message so we don't expect any responses. As metadata is sent lazily on the
    // first message we don't expect to get metadata back either.
    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .unavailable)
    }

    try await responseStream.next().assertNil()
  }

  func testErrorAfterMessage() async throws {
    let handler = self.makeHandler(observer: Self.echo(requests:responseStreamWriter:context:))

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveMessage(ByteBuffer(string: "hello"))
    }

    // Wait the metadata and message; i.e. for function to have been invoked.
    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertMetadata()
    try await responseStream.next().assertMessage()

    // Throw in an error.
    self.loop.execute {
      handler.receiveError(CancellationError())
    }

    // The RPC should end.
    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .unavailable)
    }
    try await responseStream.next().assertNil()
  }

  func testHandlerThrowsGRPCStatusOKResultsInUnknownStatus() async throws {
    // Create a user function that immediately throws GRPCStatus.ok.
    let handler = self.makeHandler { _, _, _ in
      throw GRPCStatus.ok
    }

    // Send some metadata to trigger the creation of the async task with the user function.
    self.loop.execute {
      handler.receiveMetadata([:])
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .unknown)
    }
    try await responseStream.next().assertNil()
  }

  func testUnaryHandlerReceivingMultipleMessages() async throws {
    @Sendable
    func neverCalled(_: String, _: GRPCAsyncServerCallContext) async throws -> String {
      XCTFail("Should not be called")
      return ""
    }

    let handler = GRPCAsyncServerHandler(
      context: self.makeCallHandlerContext(),
      requestDeserializer: StringDeserializer(),
      responseSerializer: StringSerializer(),
      interceptors: [],
      wrapping: neverCalled(_:_:)
    )

    defer {
      XCTAssertNoThrow(try self.loop.submit { handler.finish() }.wait())
    }

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveMessage(ByteBuffer(string: "1"))
      handler.receiveMessage(ByteBuffer(string: "2"))
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .internalError)
    }
  }

  func testServerStreamingHandlerReceivingMultipleMessages() async throws {
    @Sendable
    func neverCalled(
      _: String,
      _: GRPCAsyncResponseStreamWriter<String>,
      _: GRPCAsyncServerCallContext
    ) async throws {
      XCTFail("Should not be called")
    }

    let handler = GRPCAsyncServerHandler(
      context: self.makeCallHandlerContext(),
      requestDeserializer: StringDeserializer(),
      responseSerializer: StringSerializer(),
      interceptors: [],
      wrapping: neverCalled(_:_:_:)
    )

    defer {
      XCTAssertNoThrow(try self.loop.submit { handler.finish() }.wait())
    }

    self.loop.execute {
      handler.receiveMetadata([:])
      handler.receiveMessage(ByteBuffer(string: "1"))
      handler.receiveMessage(ByteBuffer(string: "2"))
    }

    let responseStream = self.recorder.responseSequence.makeAsyncIterator()
    try await responseStream.next().assertStatus { status, _ in
      XCTAssertEqual(status.code, .internalError)
    }
  }
}

internal final class AsyncResponseStream: GRPCServerResponseWriter {
  private let source: PassthroughMessageSource<GRPCServerResponsePart<ByteBuffer>, Never>

  internal var responseSequence: PassthroughMessageSequence<
    GRPCServerResponsePart<ByteBuffer>,
    Never
  > {
    return .init(consuming: self.source)
  }

  init() {
    self.source = PassthroughMessageSource()
  }

  func sendMetadata(
    _ metadata: HPACKHeaders,
    flush: Bool,
    promise: EventLoopPromise<Void>?
  ) {
    self.source.yield(.metadata(metadata))
    promise?.succeed(())
  }

  func sendMessage(
    _ bytes: ByteBuffer,
    metadata: MessageMetadata,
    promise: EventLoopPromise<Void>?
  ) {
    self.source.yield(.message(bytes, metadata))
    promise?.succeed(())
  }

  func sendEnd(
    status: GRPCStatus,
    trailers: HPACKHeaders,
    promise: EventLoopPromise<Void>?
  ) {
    self.source.yield(.end(status, trailers))
    self.source.finish()
    promise?.succeed(())
  }

  func stopRecording() {
    self.source.finish()
  }
}

extension Optional where Wrapped == GRPCServerResponsePart<ByteBuffer> {
  func assertNil() {
    XCTAssertNil(self)
  }

  func assertMetadata(_ verify: (HPACKHeaders) -> Void = { _ in }) {
    switch self {
    case let .some(.metadata(headers)):
      verify(headers)
    default:
      XCTFail("Expected metadata but value was \(String(describing: self))")
    }
  }

  func assertMessage(_ verify: (ByteBuffer, MessageMetadata) -> Void = { _, _ in }) {
    switch self {
    case let .some(.message(buffer, metadata)):
      verify(buffer, metadata)
    default:
      XCTFail("Expected message but value was \(String(describing: self))")
    }
  }

  func assertStatus(_ verify: (GRPCStatus, HPACKHeaders) -> Void = { _, _ in }) {
    switch self {
    case let .some(.end(status, trailers)):
      verify(status, trailers)
    default:
      XCTFail("Expected status but value was \(String(describing: self))")
    }
  }
}
#endif
