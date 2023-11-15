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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct ServerRPCExecutorTestHarness {
  struct ServerHandler<Input, Output>: Sendable {
    let fn: @Sendable (ServerRequest.Stream<Input>) async throws -> ServerResponse.Stream<Output>

    init(
      _ fn: @escaping @Sendable (
        ServerRequest.Stream<Input>
      ) async throws -> ServerResponse.Stream<Output>
    ) {
      self.fn = fn
    }

    func handle(
      _ request: ServerRequest.Stream<Input>
    ) async throws -> ServerResponse.Stream<Output> {
      try await self.fn(request)
    }

    static func throwing(_ error: any Error) -> Self {
      return Self { _ in throw error }
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
      ServerRequest.Stream<Input>
    ) async throws -> ServerResponse.Stream<Output>,
    producer: @escaping (RPCWriter<RPCRequestPart>.Closable) async throws -> Void,
    consumer: @escaping (RPCAsyncSequence<RPCResponsePart>) async throws -> Void
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
    producer: @escaping (RPCWriter<RPCRequestPart>.Closable) async throws -> Void,
    consumer: @escaping (RPCAsyncSequence<RPCResponsePart>) async throws -> Void
  ) async throws {
    let input = RPCAsyncSequence.makeBackpressuredStream(
      of: RPCRequestPart.self,
      watermarks: (16, 32)
    )

    let output = RPCAsyncSequence.makeBackpressuredStream(
      of: RPCResponsePart.self,
      watermarks: (16, 32)
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await producer(input.writer)
      }

      group.addTask {
        try await consumer(output.stream)
      }

      group.addTask {
        await ServerRPCExecutor.execute(
          stream: RPCStream(
            descriptor: MethodDescriptor(service: "foo", method: "bar"),
            inbound: input.stream,
            outbound: output.writer
          ),
          deserializer: deserializer,
          serializer: serializer,
          interceptors: self.interceptors,
          handler: { try await handler.handle($0) }
        )
      }

      try await group.waitForAll()
    }
  }

  func execute(
    handler: ServerHandler<[UInt8], [UInt8]> = .echo,
    producer: @escaping (RPCWriter<RPCRequestPart>.Closable) async throws -> Void,
    consumer: @escaping (RPCAsyncSequence<RPCResponsePart>) async throws -> Void
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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ServerRPCExecutorTestHarness.ServerHandler where Input == Output {
  static var echo: Self {
    return Self { request in
      return ServerResponse.Stream(metadata: request.metadata) { writer in
        try await writer.write(contentsOf: request.messages)
        return [:]
      }
    }
  }
}
