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
import Atomics
import XCTest

@testable import GRPCCore

/// A test harness for the ``ClientRPCExecutor``.
///
/// It provides different hooks for controlling the transport implementation and the behaviour
/// of the server to allow for flexible testing scenarios with minimal boilerplate. The harness
/// also tracks how many streams the client has opened, how many streams the server accepted, and
/// how many streams the client failed to open.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct ClientRPCExecutorTestHarness {
  private let server: ServerStreamHandler
  private let clientTransport: StreamCountingClientTransport
  private let serverTransport: StreamCountingServerTransport

  var clientStreamsOpened: Int {
    self.clientTransport.streamsOpened
  }

  var clientStreamOpenFailures: Int {
    self.clientTransport.streamFailures
  }

  var serverStreamsAccepted: Int {
    self.serverTransport.acceptedStreams
  }

  init(transport: Transport = .inProcess, server: ServerStreamHandler) {
    self.server = server

    switch transport {
    case .inProcess:
      let server = InProcessServerTransport()
      let client = server.spawnClientTransport()
      self.serverTransport = StreamCountingServerTransport(wrapping: server)
      self.clientTransport = StreamCountingClientTransport(wrapping: client)

    case .throwsOnStreamCreation(let code):
      let server = InProcessServerTransport()  // Will never be called.
      let client = ThrowOnStreamCreationTransport(code: code)
      self.serverTransport = StreamCountingServerTransport(wrapping: server)
      self.clientTransport = StreamCountingClientTransport(wrapping: client)
    }
  }

  enum Transport {
    case inProcess
    case throwsOnStreamCreation(code: RPCError.Code)
  }

  func unary(
    request: ClientRequest.Single<[UInt8]>,
    configuration: ClientRPCExecutionConfiguration? = nil,
    handler: @escaping @Sendable (ClientResponse.Single<[UInt8]>) async throws -> Void
  ) async throws {
    try await self.bidirectional(
      request: ClientRequest.Stream(single: request),
      configuration: configuration
    ) { response in
      try await handler(ClientResponse.Single(stream: response))
    }
  }

  func clientStreaming(
    request: ClientRequest.Stream<[UInt8]>,
    configuration: ClientRPCExecutionConfiguration? = nil,
    handler: @escaping @Sendable (ClientResponse.Single<[UInt8]>) async throws -> Void
  ) async throws {
    try await self.bidirectional(
      request: request,
      configuration: configuration
    ) { response in
      try await handler(ClientResponse.Single(stream: response))
    }
  }

  func serverStreaming(
    request: ClientRequest.Single<[UInt8]>,
    configuration: ClientRPCExecutionConfiguration? = nil,
    handler: @escaping @Sendable (ClientResponse.Stream<[UInt8]>) async throws -> Void
  ) async throws {
    try await self.bidirectional(
      request: ClientRequest.Stream(single: request),
      configuration: configuration
    ) { response in
      try await handler(response)
    }
  }

  func bidirectional(
    request: ClientRequest.Stream<[UInt8]>,
    configuration: ClientRPCExecutionConfiguration? = nil,
    handler: @escaping @Sendable (ClientResponse.Stream<[UInt8]>) async throws -> Void
  ) async throws {
    try await self.execute(
      request: request,
      serializer: IdentitySerializer(),
      deserializer: IdentityDeserializer(),
      configuration: configuration,
      handler: handler
    )
  }

  private func execute<Input, Output>(
    request: ClientRequest.Stream<Input>,
    serializer: some MessageSerializer<Input>,
    deserializer: some MessageDeserializer<Output>,
    configuration: ClientRPCExecutionConfiguration?,
    handler: @escaping @Sendable (ClientResponse.Stream<Output>) async throws -> Void
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await withThrowingTaskGroup(of: Void.self) { serverGroup in
          let streams = try await self.serverTransport.listen()
          for try await stream in streams {
            serverGroup.addTask {
              try await self.server.handle(stream: stream)
            }
          }
        }
      }

      group.addTask {
        try await self.clientTransport.connect(lazily: false)
      }

      let executionConfiguration: ClientRPCExecutionConfiguration
      if let configuration = configuration {
        executionConfiguration = configuration
      } else {
        executionConfiguration = ClientRPCExecutionConfiguration(executionPolicy: nil, timeout: nil)
      }

      // Execute the request.
      try await ClientRPCExecutor.execute(
        request: request,
        method: MethodDescriptor(service: "foo", method: "bar"),
        configuration: executionConfiguration,
        serializer: serializer,
        deserializer: deserializer,
        transport: self.clientTransport,
        interceptors: [],
        handler: handler
      )

      // Close the client so the server can finish.
      self.clientTransport.close()
      self.serverTransport.stopListening()
      group.cancelAll()
    }
  }
}
