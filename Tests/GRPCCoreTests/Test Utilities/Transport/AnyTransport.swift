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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct AnyClientTransport: ClientTransport, Sendable {
  typealias Inbound = RPCAsyncSequence<RPCResponsePart>
  typealias Outbound = RPCWriter<RPCRequestPart>.Closable

  private let _retryThrottle: @Sendable () -> RetryThrottle?
  private let _withStream:
    @Sendable (
      _ method: MethodDescriptor,
      _ options: CallOptions,
      _ body: (RPCStream<Inbound, Outbound>) async throws -> Any
    ) async throws -> Any
  private let _connect: @Sendable (Bool) async throws -> Void
  private let _close: @Sendable () -> Void
  private let _configuration: @Sendable (MethodDescriptor) -> MethodConfig?

  init<Transport: ClientTransport>(wrapping transport: Transport)
  where Transport.Inbound == Inbound, Transport.Outbound == Outbound {
    self._retryThrottle = { transport.retryThrottle }
    self._withStream = { descriptor, options, closure in
      try await transport.withStream(descriptor: descriptor, options: options) { stream in
        try await closure(stream) as Any
      }
    }

    self._connect = { lazily in
      try await transport.connect(lazily: lazily)
    }

    self._close = {
      transport.close()
    }

    self._configuration = { descriptor in
      transport.configuration(forMethod: descriptor)
    }
  }

  var retryThrottle: RetryThrottle? {
    self._retryThrottle()
  }

  func connect(lazily: Bool) async throws {
    try await self._connect(lazily)
  }

  func close() {
    self._close()
  }

  func withStream<T>(
    descriptor: MethodDescriptor,
    options: CallOptions,
    _ closure: (RPCStream<Inbound, Outbound>) async throws -> T
  ) async throws -> T {
    let result = try await self._withStream(descriptor, options, closure)
    return result as! T
  }

  func configuration(
    forMethod descriptor: MethodDescriptor
  ) -> MethodConfig? {
    self._configuration(descriptor)
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct AnyServerTransport: ServerTransport, Sendable {
  typealias Inbound = RPCAsyncSequence<RPCRequestPart>
  typealias Outbound = RPCWriter<RPCResponsePart>.Closable

  private let _listen: @Sendable () async throws -> RPCAsyncSequence<RPCStream<Inbound, Outbound>>
  private let _stopListening: @Sendable () -> Void

  init<Transport: ServerTransport>(wrapping transport: Transport) {
    self._listen = {
      let mapped = try await transport.listen().map { stream in
        return RPCStream(
          descriptor: stream.descriptor,
          inbound: RPCAsyncSequence(wrapping: stream.inbound),
          outbound: RPCWriter.Closable(wrapping: stream.outbound)
        )
      }

      return RPCAsyncSequence(wrapping: mapped)
    }

    self._stopListening = {
      transport.stopListening()
    }
  }

  func listen() async throws -> RPCAsyncSequence<RPCStream<Inbound, Outbound>> {
    try await self._listen()
  }

  func stopListening() {
    self._stopListening()
  }
}
