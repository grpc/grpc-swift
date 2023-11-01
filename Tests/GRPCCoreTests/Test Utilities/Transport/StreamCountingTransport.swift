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

@testable import GRPCCore

struct StreamCountingClientTransport: ClientTransport, Sendable {
  typealias Inbound = RPCAsyncSequence<RPCResponsePart>
  typealias Outbound = RPCWriter<RPCRequestPart>.Closable

  private let transport: AnyClientTransport
  private let _streamsOpened = ManagedAtomic(0)
  private let _streamFailures = ManagedAtomic(0)

  var streamsOpened: Int {
    self._streamsOpened.load(ordering: .sequentiallyConsistent)
  }

  var streamFailures: Int {
    self._streamFailures.load(ordering: .sequentiallyConsistent)
  }

  init<Transport: ClientTransport>(wrapping transport: Transport) {
    self.transport = AnyClientTransport(wrapping: transport)
  }

  var retryThrottle: RetryThrottle {
    self.transport.retryThrottle
  }

  func connect(lazily: Bool) async throws {
    try await self.transport.connect(lazily: lazily)
  }

  func close() {
    self.transport.close()
  }

  func openStream(
    descriptor: MethodDescriptor
  ) async throws -> RPCStream<Inbound, Outbound> {
    do {
      let stream = try await self.transport.openStream(descriptor: descriptor)
      self._streamsOpened.wrappingIncrement(ordering: .sequentiallyConsistent)
      return stream
    } catch {
      self._streamFailures.wrappingIncrement(ordering: .sequentiallyConsistent)
      throw error
    }
  }

  func executionConfiguration(
    forMethod descriptor: MethodDescriptor
  ) -> ClientRPCExecutionConfiguration? {
    self.transport.executionConfiguration(forMethod: descriptor)
  }
}

struct StreamCountingServerTransport: ServerTransport, Sendable {
  typealias Inbound = RPCAsyncSequence<RPCRequestPart>
  typealias Outbound = RPCWriter<RPCResponsePart>.Closable

  private let transport: AnyServerTransport
  private let _acceptedStreams = ManagedAtomic(0)

  var acceptedStreams: Int {
    self._acceptedStreams.load(ordering: .sequentiallyConsistent)
  }

  init<Transport: ServerTransport>(wrapping transport: Transport) {
    self.transport = AnyServerTransport(wrapping: transport)
  }

  func listen() async throws -> RPCAsyncSequence<RPCStream<Inbound, Outbound>> {
    let mapped = try await self.transport.listen().map { stream in
      self._acceptedStreams.wrappingIncrement(ordering: .sequentiallyConsistent)
      return stream
    }

    return RPCAsyncSequence(wrapping: mapped)
  }

  func stopListening() {
    self.transport.stopListening()
  }
}
