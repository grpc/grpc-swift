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
@testable import GRPC
import NIO
import NIOHPACK
import XCTest

final class ResponseRecorder: GRPCServerResponseWriter {
  var metadata: HPACKHeaders?
  var messages: [ByteBuffer] = []
  var status: GRPCStatus?
  var trailers: HPACKHeaders?

  func sendMetadata(_ metadata: HPACKHeaders, promise: EventLoopPromise<Void>?) {
    XCTAssertNil(self.metadata)
    self.metadata = metadata
    promise?.succeed(())
  }

  func sendMessage(
    _ bytes: ByteBuffer,
    metadata: MessageMetadata,
    promise: EventLoopPromise<Void>?
  ) {
    self.messages.append(bytes)
    promise?.succeed(())
  }

  func sendEnd(status: GRPCStatus, trailers: HPACKHeaders, promise: EventLoopPromise<Void>?) {
    XCTAssertNil(self.status)
    XCTAssertNil(self.trailers)
    self.status = status
    self.trailers = trailers
    promise?.succeed(())
  }
}

class UnaryServerHandlerTests: GRPCTestCase {
  let eventLoop = EmbeddedEventLoop()
  let allocator = ByteBufferAllocator()

  private func makeCallHandlerContext(writer: GRPCServerResponseWriter) -> CallHandlerContext {
    return CallHandlerContext(
      errorDelegate: nil,
      logger: self.logger,
      encoding: .disabled,
      eventLoop: self.eventLoop,
      path: "/ignored",
      remoteAddress: nil,
      responseWriter: writer,
      allocator: self.allocator
    )
  }

  private func makeHandler(
    writer: GRPCServerResponseWriter,
    function: @escaping (String, StatusOnlyCallContext) -> EventLoopFuture<String>
  ) -> UnaryServerHandler<StringSerializer, StringDeserializer> {
    return UnaryServerHandler(
      context: self.makeCallHandlerContext(writer: writer),
      requestDeserializer: StringDeserializer(),
      responseSerializer: StringSerializer(),
      interceptors: [],
      userFunction: function
    )
  }

  private func echo(_ request: String, context: StatusOnlyCallContext) -> EventLoopFuture<String> {
    return context.eventLoop.makeSucceededFuture(request)
  }

  private func neverComplete(
    _ request: String,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<String> {
    let scheduled = context.eventLoop.scheduleTask(deadline: .distantFuture) {
      return request
    }
    return scheduled.futureResult
  }

  private func neverCalled(
    _ request: String,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<String> {
    XCTFail("Unexpected function invocation")
    return context.eventLoop.makeFailedFuture(GRPCError.InvalidState(""))
  }

  func testHappyPath() {
    let recorder = ResponseRecorder()
    let handler = self.makeHandler(writer: recorder, function: self.echo(_:context:))

    handler.receiveMetadata([:])
    assertThat(recorder.metadata, .is([:]))

    let buffer = ByteBuffer(string: "hello")
    handler.receiveMessage(buffer)
    handler.receiveEnd()
    handler.finish()

    assertThat(recorder.messages.first, .is(buffer))
    assertThat(recorder.status, .notNil(.hasCode(.ok)))
    assertThat(recorder.trailers, .is([:]))
  }

  func testThrowingDeserializer() {
    let recorder = ResponseRecorder()
    let handler = UnaryServerHandler(
      context: self.makeCallHandlerContext(writer: recorder),
      requestDeserializer: ThrowingStringDeserializer(),
      responseSerializer: StringSerializer(),
      interceptors: [],
      userFunction: self.neverCalled(_:context:)
    )

    handler.receiveMetadata([:])
    assertThat(recorder.metadata, .is([:]))

    let buffer = ByteBuffer(string: "hello")
    handler.receiveMessage(buffer)

    assertThat(recorder.messages, .isEmpty())
    assertThat(recorder.status, .notNil(.hasCode(.internalError)))
  }

  func testThrowingSerializer() {
    let recorder = ResponseRecorder()
    let handler = UnaryServerHandler(
      context: self.makeCallHandlerContext(writer: recorder),
      requestDeserializer: StringDeserializer(),
      responseSerializer: ThrowingStringSerializer(),
      interceptors: [],
      userFunction: self.echo(_:context:)
    )

    handler.receiveMetadata([:])
    assertThat(recorder.metadata, .is([:]))

    let buffer = ByteBuffer(string: "hello")
    handler.receiveMessage(buffer)
    handler.receiveEnd()

    assertThat(recorder.messages, .isEmpty())
    assertThat(recorder.status, .notNil(.hasCode(.internalError)))
  }

  func testUserFunctionReturnsFailedFuture() {
    let recorder = ResponseRecorder()
    let handler = self.makeHandler(writer: recorder) { _, context in
      return context.eventLoop.makeFailedFuture(GRPCStatus(code: .unavailable, message: ":("))
    }

    handler.receiveMetadata([:])
    assertThat(recorder.metadata, .is([:]))

    let buffer = ByteBuffer(string: "hello")
    handler.receiveMessage(buffer)

    assertThat(recorder.messages, .isEmpty())
    assertThat(recorder.status, .notNil(.hasCode(.unavailable)))
    assertThat(recorder.status?.message, .is(":("))
  }

  func testReceiveMessageBeforeHeaders() {
    let recorder = ResponseRecorder()
    let handler = self.makeHandler(writer: recorder, function: self.neverCalled(_:context:))

    handler.receiveMessage(ByteBuffer(string: "foo"))
    assertThat(recorder.metadata, .is(.nil()))
    assertThat(recorder.messages, .isEmpty())
    assertThat(recorder.status, .notNil(.hasCode(.internalError)))
  }

  func testReceiveMultipleHeaders() {
    let recorder = ResponseRecorder()
    let handler = self.makeHandler(writer: recorder, function: self.neverCalled(_:context:))

    handler.receiveMetadata([:])
    assertThat(recorder.metadata, .is([:]))

    handler.receiveMetadata([:])
    assertThat(recorder.messages, .isEmpty())
    assertThat(recorder.status, .notNil(.hasCode(.internalError)))
  }

  func testReceiveMultipleMessages() {
    let recorder = ResponseRecorder()
    let handler = self.makeHandler(writer: recorder, function: self.neverComplete(_:context:))

    handler.receiveMetadata([:])
    assertThat(recorder.metadata, .is([:]))

    let buffer = ByteBuffer(string: "hello")
    handler.receiveMessage(buffer)
    handler.receiveEnd()
    // Send another message before the function completes.
    handler.receiveMessage(buffer)

    assertThat(recorder.messages, .isEmpty())
    assertThat(recorder.status, .notNil(.hasCode(.internalError)))
  }

  func testFinishBeforeStarting() {
    let recorder = ResponseRecorder()
    let handler = self.makeHandler(writer: recorder, function: self.neverCalled(_:context:))

    handler.finish()
    assertThat(recorder.metadata, .is(.nil()))
    assertThat(recorder.messages, .isEmpty())
    assertThat(recorder.status, .is(.nil()))
    assertThat(recorder.trailers, .is(.nil()))
  }

  func testFinishAfterHeaders() {
    let recorder = ResponseRecorder()
    let handler = self.makeHandler(writer: recorder, function: self.neverCalled(_:context:))
    handler.receiveMetadata([:])
    assertThat(recorder.metadata, .is([:]))

    handler.finish()

    assertThat(recorder.messages, .isEmpty())
    assertThat(recorder.status, .notNil(.hasCode(.unavailable)))
    assertThat(recorder.trailers, .is([:]))
  }

  func testFinishAfterMessage() {
    let recorder = ResponseRecorder()
    let handler = self.makeHandler(writer: recorder, function: self.neverComplete(_:context:))

    handler.receiveMetadata([:])
    handler.receiveMessage(ByteBuffer(string: "hello"))
    handler.finish()

    assertThat(recorder.messages, .isEmpty())
    assertThat(recorder.status, .notNil(.hasCode(.unavailable)))
    assertThat(recorder.trailers, .is([:]))
  }
}
