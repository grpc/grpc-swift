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

struct StreamCountingClientTransport: ClientTransport, Sendable {
  typealias Inbound = RPCAsyncSequence<RPCResponsePart, any Error>
  typealias Outbound = RPCWriter<RPCRequestPart>.Closable

  private let transport: AnyClientTransport
  private let _streamsOpened: AtomicCounter
  private let _streamFailures: AtomicCounter

  var streamsOpened: Int {
    self._streamsOpened.value
  }

  var streamFailures: Int {
    self._streamFailures.value
  }

  init<Transport: ClientTransport>(wrapping transport: Transport)
  where Transport.Inbound == Inbound, Transport.Outbound == Outbound {
    self.transport = AnyClientTransport(wrapping: transport)
    self._streamsOpened = AtomicCounter()
    self._streamFailures = AtomicCounter()
  }

  var retryThrottle: RetryThrottle? {
    self.transport.retryThrottle
  }

  func connect() async throws {
    try await self.transport.connect()
  }

  func beginGracefulShutdown() {
    self.transport.beginGracefulShutdown()
  }

  func withStream<T>(
    descriptor: MethodDescriptor,
    options: CallOptions,
    _ closure: (RPCStream<Inbound, Outbound>, ClientContext) async throws -> T
  ) async throws -> T {
    do {
      return try await self.transport.withStream(
        descriptor: descriptor,
        options: options
      ) { stream, context in
        self._streamsOpened.increment()
        return try await closure(stream, context)
      }
    } catch {
      self._streamFailures.increment()
      throw error
    }
  }

  func config(
    forMethod descriptor: MethodDescriptor
  ) -> MethodConfig? {
    self.transport.config(forMethod: descriptor)
  }
}

struct StreamCountingServerTransport: ServerTransport, Sendable {
  typealias Inbound = RPCAsyncSequence<RPCRequestPart, any Error>
  typealias Outbound = RPCWriter<RPCResponsePart>.Closable

  private let transport: AnyServerTransport
  private let _acceptedStreams: AtomicCounter

  var acceptedStreamsCount: Int {
    self._acceptedStreams.value
  }

  init<Transport: ServerTransport>(wrapping transport: Transport) {
    self.transport = AnyServerTransport(wrapping: transport)
    self._acceptedStreams = AtomicCounter()
  }

  func listen(
    streamHandler: @escaping @Sendable (
      _ stream: RPCStream<Inbound, Outbound>,
      _ context: ServerContext
    ) async -> Void
  ) async throws {
    try await self.transport.listen { stream, context in
      self._acceptedStreams.increment()
      await streamHandler(stream, context)
    }
  }

  func beginGracefulShutdown() {
    self.transport.beginGracefulShutdown()
  }
}
