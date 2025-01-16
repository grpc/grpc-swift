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
@testable import GRPCCore

struct AnyClientTransport: ClientTransport, Sendable {
  typealias Inbound = RPCAsyncSequence<RPCResponsePart, any Error>
  typealias Outbound = RPCWriter<RPCRequestPart>.Closable

  private let _retryThrottle: @Sendable () -> RetryThrottle?
  private let _withStream:
    @Sendable (
      _ method: MethodDescriptor,
      _ options: CallOptions,
      _ body: (RPCStream<Inbound, Outbound>, ClientContext) async throws -> (any Sendable)
    ) async throws -> Any
  private let _connect: @Sendable () async throws -> Void
  private let _close: @Sendable () -> Void
  private let _configuration: @Sendable (MethodDescriptor) -> MethodConfig?

  init<Transport: ClientTransport>(wrapping transport: Transport)
  where Transport.Inbound == Inbound, Transport.Outbound == Outbound {
    self._retryThrottle = { transport.retryThrottle }
    self._withStream = { descriptor, options, closure in
      try await transport.withStream(descriptor: descriptor, options: options) { stream, context in
        try await closure(stream, context) as (any Sendable)
      }
    }

    self._connect = {
      try await transport.connect()
    }

    self._close = {
      transport.beginGracefulShutdown()
    }

    self._configuration = { descriptor in
      transport.config(forMethod: descriptor)
    }
  }

  var retryThrottle: RetryThrottle? {
    self._retryThrottle()
  }

  func connect() async throws {
    try await self._connect()
  }

  func beginGracefulShutdown() {
    self._close()
  }

  func withStream<T>(
    descriptor: MethodDescriptor,
    options: CallOptions,
    _ closure: (RPCStream<Inbound, Outbound>, ClientContext) async throws -> T
  ) async throws -> T {
    let result = try await self._withStream(descriptor, options, closure)
    return result as! T
  }

  func config(
    forMethod descriptor: MethodDescriptor
  ) -> MethodConfig? {
    self._configuration(descriptor)
  }
}

struct AnyServerTransport: ServerTransport, Sendable {
  typealias Inbound = RPCAsyncSequence<RPCRequestPart, any Error>
  typealias Outbound = RPCWriter<RPCResponsePart>.Closable

  private let _listen:
    @Sendable (
      @escaping @Sendable (
        _ stream: RPCStream<Inbound, Outbound>,
        _ context: ServerContext
      ) async -> Void
    ) async throws -> Void
  private let _stopListening: @Sendable () -> Void

  init<Transport: ServerTransport>(wrapping transport: Transport) {
    self._listen = { streamHandler in try await transport.listen(streamHandler: streamHandler) }
    self._stopListening = { transport.beginGracefulShutdown() }
  }

  func listen(
    streamHandler: @escaping @Sendable (
      _ stream: RPCStream<Inbound, Outbound>,
      _ context: ServerContext
    ) async -> Void
  ) async throws {
    try await self._listen(streamHandler)
  }

  func beginGracefulShutdown() {
    self._stopListening()
  }
}
