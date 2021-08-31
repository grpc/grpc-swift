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
#if compiler(>=5.5)

@testable import GRPC
import NIOCore
import XCTest

// MARK: - Tests

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
class AsyncServerHandlerTests: ServerHandlerTestCaseBase {
  private func makeHandler(
    encoding: ServerMessageEncoding = .disabled,
    observer: @escaping @Sendable(
      GRPCAsyncStream<String>,
      GRPCAsyncResponseStreamWriter<String>,
      GRPCAsyncServerCallContext
    ) async throws -> Void
  ) -> GRPCAsyncServerHandler<StringSerializer, StringDeserializer> {
    return GRPCAsyncServerHandler(
      context: self.makeCallHandlerContext(encoding: encoding),
      requestDeserializer: StringDeserializer(),
      responseSerializer: StringSerializer(),
      interceptors: [],
      observer: observer
    )
  }

  @Sendable private func echo(
    requests: GRPCAsyncStream<String>,
    responseStreamWriter: GRPCAsyncResponseStreamWriter<String>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await message in requests {
      try await responseStreamWriter.send(message)
    }
  }

  @Sendable private func neverReceivesMessage(
    requests: GRPCAsyncStream<String>,
    responseStreamWriter: GRPCAsyncResponseStreamWriter<String>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await message in requests {
      XCTFail("Unexpected message: '\(message)'")
    }
  }

  @Sendable private func neverCalled(
    requests: GRPCAsyncStream<String>,
    responseStreamWriter: GRPCAsyncResponseStreamWriter<String>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    XCTFail("This observer should never be called")
  }

  func testHappyPath() { XCTAsyncTest {
    let handler = self.makeHandler(
      observer: self.echo(requests:responseStreamWriter:context:)
    )

    handler.receiveMetadata([:])
    await assertThat(self.recorder.metadata, .is([:]))

    handler.receiveMessage(ByteBuffer(string: "1"))
    handler.receiveMessage(ByteBuffer(string: "2"))
    handler.receiveMessage(ByteBuffer(string: "3"))
    handler.receiveEnd()

    // Wait for user handler to finish.
    await handler.task?.value

    handler.finish()

    await assertThat(
      self.recorder.messages,
      .is([ByteBuffer(string: "1"), ByteBuffer(string: "2"), ByteBuffer(string: "3")])
    )
    await assertThat(self.recorder.messageMetadata.map { $0.compress }, .is([false, false, false]))
    await assertThat(self.recorder.status, .notNil(.hasCode(.ok)))
    await assertThat(self.recorder.trailers, .is([:]))
  } }

  func testHappyPathWithCompressionEnabled() { XCTAsyncTest {
    let handler = self.makeHandler(
      encoding: .enabled(.init(decompressionLimit: .absolute(.max))),
      observer: self.echo(requests:responseStreamWriter:context:)
    )

    handler.receiveMetadata([:])
    handler.receiveMessage(ByteBuffer(string: "1"))
    handler.receiveMessage(ByteBuffer(string: "2"))
    handler.receiveMessage(ByteBuffer(string: "3"))
    handler.receiveEnd()

    // Wait for user handler to finish.
    await handler.task?.value

    await assertThat(
      self.recorder.messages,
      .is([ByteBuffer(string: "1"), ByteBuffer(string: "2"), ByteBuffer(string: "3")])
    )
    await assertThat(self.recorder.messageMetadata.map { $0.compress }, .is([true, true, true]))
  } }

  func testHappyPathWithCompressionEnabledButDisabledByCaller() { XCTAsyncTest {
    let handler = self.makeHandler(
      encoding: .enabled(.init(decompressionLimit: .absolute(.max)))
    ) { requests, responseStreamWriter, context in
      context.compressionEnabled = false
      return try await self.echo(
        requests: requests,
        responseStreamWriter: responseStreamWriter,
        context: context
      )
    }

    handler.receiveMetadata([:])
    handler.receiveMessage(ByteBuffer(string: "1"))
    handler.receiveMessage(ByteBuffer(string: "2"))
    handler.receiveMessage(ByteBuffer(string: "3"))
    handler.receiveEnd()

    // Wait for user handler to finish.
    await handler.task?.value

    await assertThat(
      self.recorder.messages,
      .is([ByteBuffer(string: "1"), ByteBuffer(string: "2"), ByteBuffer(string: "3")])
    )
    await assertThat(self.recorder.messageMetadata.map { $0.compress }, .is([false, false, false]))
  } }

  func testTaskOnlyCreatedAfterHeaders() { XCTAsyncTest {
    let handler = self.makeHandler(observer: self.echo(requests:responseStreamWriter:context:))

    await assertThat(handler.task, .is(.nil()))

    handler.receiveMetadata([:])

    await assertThat(handler.task, .is(.notNil()))
  } }

  func testThrowingDeserializer() { XCTAsyncTest {
    let handler = GRPCAsyncServerHandler(
      context: self.makeCallHandlerContext(),
      requestDeserializer: ThrowingStringDeserializer(),
      responseSerializer: StringSerializer(),
      interceptors: [],
      observer: self.neverReceivesMessage(requests:responseStreamWriter:context:)
    )

    handler.receiveMetadata([:])

    // Wait for the async user function to have processed the metadata.
    try self.recorder.recordedMetadataPromise.futureResult.wait()

    await assertThat(self.recorder.metadata, .is([:]))

    let buffer = ByteBuffer(string: "hello")
    handler.receiveMessage(buffer)

    // Wait for user handler to finish.
    await handler.task?.value

    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .notNil(.hasCode(.internalError)))
  } }

  func testThrowingSerializer() { XCTAsyncTest {
    let handler = GRPCAsyncServerHandler(
      context: self.makeCallHandlerContext(),
      requestDeserializer: StringDeserializer(),
      responseSerializer: ThrowingStringSerializer(),
      interceptors: [],
      observer: self.echo(requests:responseStreamWriter:context:)
    )

    handler.receiveMetadata([:])
    await assertThat(self.recorder.metadata, .is([:]))

    let buffer = ByteBuffer(string: "hello")
    handler.receiveMessage(buffer)
    handler.receiveEnd()

    // Wait for user handler to finish.
    await handler.task?.value

    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .notNil(.hasCode(.internalError)))
  } }

  func testReceiveMessageBeforeHeaders() { XCTAsyncTest {
    let handler = self
      .makeHandler(observer: self.neverCalled(requests:responseStreamWriter:context:))

    handler.receiveMessage(ByteBuffer(string: "foo"))

    await handler.task?.value

    await assertThat(self.recorder.metadata, .is(.nil()))
    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .notNil(.hasCode(.internalError)))
  } }

  // TODO: Running this 1000 times shows up a segfault in NIO event loop group.
  func testReceiveMultipleHeaders() { XCTAsyncTest {
    let handler = self
      .makeHandler(observer: self.neverReceivesMessage(requests:responseStreamWriter:context:))

    handler.receiveMetadata([:])

    // Wait for the async user function to have processed the metadata.
    try self.recorder.recordedMetadataPromise.futureResult.wait()

    await assertThat(self.recorder.metadata, .is([:]))

    handler.receiveMetadata([:])

    // Wait for user handler to finish.
    await handler.task?.value

    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .notNil(.hasCode(.internalError)))
  } }

  func testFinishBeforeStarting() { XCTAsyncTest {
    let handler = self
      .makeHandler(observer: self.neverCalled(requests:responseStreamWriter:context:))

    handler.finish()
    await assertThat(self.recorder.metadata, .is(.nil()))
    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .is(.nil()))
    await assertThat(self.recorder.trailers, .is(.nil()))
  } }

  func testFinishAfterHeaders() { XCTAsyncTest {
    let handler = self.makeHandler(observer: self.echo(requests:responseStreamWriter:context:))
    handler.receiveMetadata([:])

    // Wait for the async user function to have processed the metadata.
    try self.recorder.recordedMetadataPromise.futureResult.wait()

    await assertThat(self.recorder.metadata, .is([:]))

    handler.finish()

    // Wait for user handler to finish.
    await handler.task?.value

    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .notNil(.hasCode(.unavailable)))
    await assertThat(self.recorder.trailers, .is([:]))
  } }

  func testFinishAfterMessage() { XCTAsyncTest {
    let handler = self.makeHandler(observer: self.echo(requests:responseStreamWriter:context:))

    handler.receiveMetadata([:])
    handler.receiveMessage(ByteBuffer(string: "hello"))

    // Wait for the async user function to have processed the message.
    try self.recorder.recordedMessagePromise.futureResult.wait()

    handler.finish()

    // Wait for user handler to finish.
    await handler.task?.value

    await assertThat(self.recorder.messages.first, .is(ByteBuffer(string: "hello")))
    await assertThat(self.recorder.status, .notNil(.hasCode(.unavailable)))
    await assertThat(self.recorder.trailers, .is([:]))
  } }

  func testHandlerThrowsGRPCStatusOK() { XCTAsyncTest {
    // Create a user function that immediately throws GRPCStatus.ok.
    let handler = self.makeHandler { requests, responseStreamWriter, context in
      throw GRPCStatus.ok
    }

    // Send some metadata to trigger the creation of the async task with the user function.
    handler.receiveMetadata([:])

    // Wait for user handler to finish (it's gonna throw immediately).
    await assertThat(await handler.task?.value, .notNil())

    // Check the status is OK.
    await assertThat(self.recorder.status, .notNil(.hasCode(.ok)))
  } }
}

#endif
