/*
 * Copyright 2023, gRPC Authors All rights reserved.
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
import XCTest

@testable import GRPCCore

struct ServerRPCExecutorTestHarness {
  struct ServerHandler<Input: Sendable, Output: Sendable>: Sendable {
    let fn:
      @Sendable (
        _ request: StreamingServerRequest<Input>,
        _ context: ServerContext
      ) async throws -> StreamingServerResponse<Output>

    init(
      _ fn: @escaping @Sendable (
        _ request: StreamingServerRequest<Input>,
        _ context: ServerContext
      ) async throws -> StreamingServerResponse<Output>
    ) {
      self.fn = fn
    }

    func handle(
      _ request: StreamingServerRequest<Input>,
      _ context: ServerContext
    ) async throws -> StreamingServerResponse<Output> {
      try await self.fn(request, context)
    }

    static func throwing(_ error: any Error) -> Self {
      return Self { _, _ in throw error }
    }
  }

  let interceptors: [any ServerInterceptor]

  init(interceptors: [any ServerInterceptor] = []) {
    self.interceptors = interceptors
  }

  func execute<Input, Output>(
    deserializer: some MessageDeserializer<Input>,
    serializer: some MessageSerializer<Output>,
    handler: @escaping @Sendable (
      StreamingServerRequest<Input>,
      ServerContext
    ) async throws -> StreamingServerResponse<Output>,
    producer: @escaping @Sendable (
      RPCWriter<RPCRequestPart>.Closable
    ) async throws -> Void,
    consumer: @escaping @Sendable (
      RPCAsyncSequence<RPCResponsePart, any Error>
    ) async throws -> Void
  ) async throws {
    try await self.execute(
      deserializer: deserializer,
      serializer: serializer,
      handler: .init(handler),
      producer: producer,
      consumer: consumer
    )
  }

  func execute<Input, Output>(
    deserializer: some MessageDeserializer<Input>,
    serializer: some MessageSerializer<Output>,
    handler: ServerHandler<Input, Output>,
    producer: @escaping @Sendable (
      RPCWriter<RPCRequestPart>.Closable
    ) async throws -> Void,
    consumer: @escaping @Sendable (
      RPCAsyncSequence<RPCResponsePart, any Error>
    ) async throws -> Void
  ) async throws {
    let input = GRPCAsyncThrowingStream.makeStream(of: RPCRequestPart.self)
    let output = GRPCAsyncThrowingStream.makeStream(of: RPCResponsePart.self)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await producer(RPCWriter.Closable(wrapping: input.continuation))
      }

      group.addTask {
        try await consumer(RPCAsyncSequence(wrapping: output.stream))
      }

      group.addTask {
        await withServerContextRPCCancellationHandle { cancellation in
          let context = ServerContext(
            descriptor: MethodDescriptor(service: "foo", method: "bar"),
            cancellation: cancellation
          )

          await ServerRPCExecutor.execute(
            context: context,
            stream: RPCStream(
              descriptor: context.descriptor,
              inbound: RPCAsyncSequence(wrapping: input.stream),
              outbound: RPCWriter.Closable(wrapping: output.continuation)
            ),
            deserializer: deserializer,
            serializer: serializer,
            interceptors: self.interceptors,
            handler: { stream, context in
              try await handler.handle(stream, context)
            }
          )
        }
      }

      try await group.waitForAll()
    }
  }

  func execute(
    handler: ServerHandler<[UInt8], [UInt8]> = .echo,
    producer: @escaping @Sendable (
      RPCWriter<RPCRequestPart>.Closable
    ) async throws -> Void,
    consumer: @escaping @Sendable (
      RPCAsyncSequence<RPCResponsePart, any Error>
    ) async throws -> Void
  ) async throws {
    try await self.execute(
      deserializer: IdentityDeserializer(),
      serializer: IdentitySerializer(),
      handler: handler,
      producer: producer,
      consumer: consumer
    )
  }
}

extension ServerRPCExecutorTestHarness.ServerHandler where Input == Output {
  static var echo: Self {
    return Self { request, context in
      return StreamingServerResponse(metadata: request.metadata) { writer in
        try await writer.write(contentsOf: request.messages)
        return [:]
      }
    }
  }
}
