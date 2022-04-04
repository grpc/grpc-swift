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
import XCTest

// MARK: - Tests

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
class AsyncServerHandlerTests: ServerHandlerTestCaseBase {
  private func makeHandler(
    encoding: ServerMessageEncoding = .disabled,
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
      interceptors: [],
      userHandler: observer
    )
  }

  @Sendable private func echo(
    requests: GRPCAsyncRequestStream<String>,
    responseStreamWriter: GRPCAsyncResponseStreamWriter<String>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await message in requests {
      try await responseStreamWriter.send(message)
    }
  }

  @Sendable private func neverReceivesMessage(
    requests: GRPCAsyncRequestStream<String>,
    responseStreamWriter: GRPCAsyncResponseStreamWriter<String>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await message in requests {
      XCTFail("Unexpected message: '\(message)'")
    }
  }

  @Sendable private func neverCalled(
    requests: GRPCAsyncRequestStream<String>,
    responseStreamWriter: GRPCAsyncResponseStreamWriter<String>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    XCTFail("This observer should never be called")
  }

  func testHappyPath() async throws {
    let handler = self.makeHandler(
      observer: self.echo(requests:responseStreamWriter:context:)
    )

    handler.receiveMetadata([:])
    handler.receiveMessage(ByteBuffer(string: "1"))
    handler.receiveMessage(ByteBuffer(string: "2"))
    handler.receiveMessage(ByteBuffer(string: "3"))
    handler.receiveEnd()

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    handler.finish()

    await assertThat(self.recorder.metadata, .is([:]))
    await assertThat(
      self.recorder.messages,
      .is([ByteBuffer(string: "1"), ByteBuffer(string: "2"), ByteBuffer(string: "3")])
    )
    await assertThat(self.recorder.messageMetadata.map { $0.compress }, .is([false, false, false]))
    await assertThat(self.recorder.status, .notNil(.hasCode(.ok)))
    await assertThat(self.recorder.trailers, .is([:]))
  }

  func testHappyPathWithCompressionEnabled() async throws {
    let handler = self.makeHandler(
      encoding: .enabled(.init(decompressionLimit: .absolute(.max))),
      observer: self.echo(requests:responseStreamWriter:context:)
    )

    handler.receiveMetadata([:])
    handler.receiveMessage(ByteBuffer(string: "1"))
    handler.receiveMessage(ByteBuffer(string: "2"))
    handler.receiveMessage(ByteBuffer(string: "3"))
    handler.receiveEnd()

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(
      self.recorder.messages,
      .is([ByteBuffer(string: "1"), ByteBuffer(string: "2"), ByteBuffer(string: "3")])
    )
    await assertThat(self.recorder.messageMetadata.map { $0.compress }, .is([true, true, true]))
  }

  func testHappyPathWithCompressionEnabledButDisabledByCaller() async throws {
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

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(
      self.recorder.messages,
      .is([ByteBuffer(string: "1"), ByteBuffer(string: "2"), ByteBuffer(string: "3")])
    )
    await assertThat(self.recorder.messageMetadata.map { $0.compress }, .is([false, false, false]))
  }

  func testResponseHeadersAndTrailersSentFromContext() async throws {
    let handler = self.makeHandler { _, responseStreamWriter, context in
      context.initialResponseMetadata = ["pontiac": "bandit"]
      try await responseStreamWriter.send("1")
      context.trailingResponseMetadata = ["disco": "strangler"]
    }
    handler.receiveMetadata([:])
    handler.receiveEnd()

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(self.recorder.metadata, .is(["pontiac": "bandit"]))
    await assertThat(self.recorder.trailers, .is(["disco": "strangler"]))
  }

  func testResponseHeadersDroppedIfSetAfterFirstResponse() async throws {
    let handler = self.makeHandler { _, responseStreamWriter, context in
      try await responseStreamWriter.send("1")
      context.initialResponseMetadata = ["pontiac": "bandit"]
      context.trailingResponseMetadata = ["disco": "strangler"]
    }
    handler.receiveMetadata([:])
    handler.receiveEnd()

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(self.recorder.metadata, .is([:]))
    await assertThat(self.recorder.trailers, .is(["disco": "strangler"]))
  }

  func testTaskOnlyCreatedAfterHeaders() async throws {
    let handler = self.makeHandler(observer: self.echo(requests:responseStreamWriter:context:))

    await assertThat(handler.userHandlerTask, .nil())

    handler.receiveMetadata([:])

    await assertThat(handler.userHandlerTask, .notNil())
  }

  func testThrowingDeserializer() async throws {
    let handler = AsyncServerHandler(
      context: self.makeCallHandlerContext(),
      requestDeserializer: ThrowingStringDeserializer(),
      responseSerializer: StringSerializer(),
      interceptors: [],
      userHandler: self.neverReceivesMessage(requests:responseStreamWriter:context:)
    )

    handler.receiveMetadata([:])
    handler.receiveMessage(ByteBuffer(string: "hello"))

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(self.recorder.metadata, .nil())
    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .notNil(.hasCode(.internalError)))
  }

  func testThrowingSerializer() async throws {
    let handler = AsyncServerHandler(
      context: self.makeCallHandlerContext(),
      requestDeserializer: StringDeserializer(),
      responseSerializer: ThrowingStringSerializer(),
      interceptors: [],
      userHandler: self.echo(requests:responseStreamWriter:context:)
    )

    handler.receiveMetadata([:])
    handler.receiveMessage(ByteBuffer(string: "hello"))
    handler.receiveEnd()

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(self.recorder.metadata, .is([:]))
    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .notNil(.hasCode(.internalError)))
  }

  func testReceiveMessageBeforeHeaders() async throws {
    let handler = self
      .makeHandler(observer: self.neverCalled(requests:responseStreamWriter:context:))

    handler.receiveMessage(ByteBuffer(string: "foo"))

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(self.recorder.metadata, .nil())
    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .notNil(.hasCode(.internalError)))
  }

  func testReceiveMultipleHeaders() async throws {
    let handler = self
      .makeHandler(observer: self.neverReceivesMessage(requests:responseStreamWriter:context:))

    handler.receiveMetadata([:])
    handler.receiveMetadata([:])

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(self.recorder.metadata, .nil())
    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .notNil(.hasCode(.internalError)))
  }

  func testFinishBeforeStarting() async throws {
    let handler = self
      .makeHandler(observer: self.neverCalled(requests:responseStreamWriter:context:))

    handler.finish()
    await assertThat(self.recorder.metadata, .nil())
    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .nil())
    await assertThat(self.recorder.trailers, .nil())
  }

  func testFinishAfterHeaders() async throws {
    let handler = self.makeHandler(observer: self.echo(requests:responseStreamWriter:context:))

    handler.receiveMetadata([:])
    handler.finish()

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(self.recorder.metadata, .nil())
    await assertThat(self.recorder.messages, .isEmpty())
    await assertThat(self.recorder.status, .nil())
    await assertThat(self.recorder.trailers, .nil())
  }

  func testFinishAfterMessage() async throws {
    let handler = self.makeHandler(observer: self.echo(requests:responseStreamWriter:context:))

    handler.receiveMetadata([:])
    handler.receiveMessage(ByteBuffer(string: "hello"))

    // Wait for the async user function to have processed the message.
    try self.recorder.recordedMessagePromise.futureResult.wait()

    handler.finish()

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(self.recorder.messages.first, .is(ByteBuffer(string: "hello")))
    await assertThat(self.recorder.status, .nil())
    await assertThat(self.recorder.trailers, .nil())
  }

  func testErrorAfterHeaders() async throws {
    let handler = self.makeHandler(observer: self.echo(requests:responseStreamWriter:context:))

    handler.receiveMetadata([:])
    handler.receiveError(CancellationError())

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(self.recorder.status, .notNil(.hasCode(.unavailable)))
    await assertThat(self.recorder.trailers, .is([:]))
  }

  func testErrorAfterMessage() async throws {
    let handler = self.makeHandler(observer: self.echo(requests:responseStreamWriter:context:))

    handler.receiveMetadata([:])
    handler.receiveMessage(ByteBuffer(string: "hello"))

    // Wait for the async user function to have processed the message.
    try self.recorder.recordedMessagePromise.futureResult.wait()

    handler.receiveError(CancellationError())

    // Wait for tasks to finish.
    await handler.userHandlerTask?.value

    await assertThat(self.recorder.messages.first, .is(ByteBuffer(string: "hello")))
    await assertThat(self.recorder.status, .notNil(.hasCode(.unavailable)))
    await assertThat(self.recorder.trailers, .is([:]))
  }

  func testHandlerThrowsGRPCStatusOKResultsInUnknownStatus() async throws {
    // Create a user function that immediately throws GRPCStatus.ok.
    let handler = self.makeHandler { _, _, _ in
      throw GRPCStatus.ok
    }

    // Send some metadata to trigger the creation of the async task with the user function.
    handler.receiveMetadata([:])

    // Wait for user handler to finish (it's gonna throw immediately).
    await assertThat(await handler.userHandlerTask?.value, .notNil())

    // Check the status is `.unknown`.
    await assertThat(self.recorder.status, .notNil(.hasCode(.unknown)))
  }

  func testResponseStreamDrain() async throws {
    // Set up echo handler.
    let handler = self.makeHandler(
      observer: self.echo(requests:responseStreamWriter:context:)
    )

    // Send some metadata to trigger the creation of the async task with the user function.
    handler.receiveMetadata([:])

    // Send two requests and end, pausing the writer in the middle.
    switch handler.state {
    case let .active(activeState):
      handler.receiveMessage(ByteBuffer(string: "diaz"))
      await activeState.responseStreamWriter.asyncWriter.toggleWritability()
      handler.receiveMessage(ByteBuffer(string: "santiago"))
      handler.receiveEnd()
      await activeState.responseStreamWriter.asyncWriter.toggleWritability()
      await handler.userHandlerTask?.value
      _ = try await activeState._userHandlerPromise.futureResult.get()
    default:
      XCTFail("Unexpected handler state: \(handler.state)")
    }

    handler.finish()

    await assertThat(self.recorder.messages, .is([
      ByteBuffer(string: "diaz"),
      ByteBuffer(string: "santiago"),
    ]))
    await assertThat(self.recorder.status, .notNil(.hasCode(.ok)))
  }
}
#endif
