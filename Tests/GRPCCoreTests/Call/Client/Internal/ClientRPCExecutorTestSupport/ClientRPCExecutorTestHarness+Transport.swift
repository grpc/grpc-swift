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

// TODO: replace with real in-process transport

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class TestingClientTransport: ClientTransport, Sendable {
  typealias Inbound = RPCAsyncSequence<RPCResponsePart>
  typealias Outbound = RPCWriter<RPCRequestPart>.Closable

  let retryThrottle: RetryThrottle

  private let state: LockedValueBox<State>
  private enum State {
    case unconnected(TestingServerTransport)
    case connected(TestingServerTransport)
    case closed
  }

  fileprivate init(server: TestingServerTransport, throttle: RetryThrottle) {
    self.state = LockedValueBox(.unconnected(server))
    self.retryThrottle = throttle
  }

  deinit {
    self.state.withLockedValue { state in
      switch state {
      case .unconnected(let server), .connected(let server):
        server.stopListening()
      case .closed:
        ()
      }
    }
  }

  func connect(lazily: Bool) async throws {
    try self.state.withLockedValue { state in
      switch state {
      case let .unconnected(server):
        state = .connected(server)

      case .connected:
        ()

      case .closed:
        throw RPCError(
          code: .failedPrecondition,
          message: "Can't connect to server, transport is closed."
        )
      }
    }
  }

  func close() {
    self.state.withLockedValue { state in
      switch state {
      case .unconnected(let server), .connected(let server):
        state = .closed
        server.stopListening()

      case .closed:
        ()
      }
    }
  }

  func executionConfiguration(
    forMethod descriptor: MethodDescriptor
  ) -> ClientRPCExecutionConfiguration? {
    nil
  }

  func openStream(
    descriptor: MethodDescriptor
  ) async throws -> RPCStream<Inbound, Outbound> {
    let request = RPCAsyncSequence<RPCRequestPart>.makeBackpressuredStream(watermarks: (16, 32))
    let response = RPCAsyncSequence<RPCResponsePart>.makeBackpressuredStream(watermarks: (16, 32))

    let clientStream = RPCStream(
      descriptor: descriptor,
      inbound: response.stream,
      outbound: request.writer
    )

    let serverStream = RPCStream(
      descriptor: descriptor,
      inbound: request.stream,
      outbound: response.writer
    )

    let error: RPCError? = self.state.withLockedValue { state in
      switch state {
      case .connected(let transport):
        transport.acceptStream(serverStream)
        return nil

      case .unconnected:
        return RPCError(
          code: .failedPrecondition,
          message: "The client transport must be connected before streams can be created."
        )

      case .closed:
        return RPCError(code: .failedPrecondition, message: "The client transport is closed.")
      }
    }

    if let error = error {
      serverStream.outbound.finish()
      clientStream.outbound.finish()
      throw error
    } else {
      return clientStream
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class TestingServerTransport: ServerTransport, Sendable {
  typealias Inbound = RPCAsyncSequence<RPCRequestPart>
  typealias Outbound = RPCWriter<RPCResponsePart>.Closable

  typealias Stream = RPCStream<Inbound, Outbound>
  private let accepted:
    (stream: AsyncStream<Stream>, continuation: AsyncStream<Stream>.Continuation)

  init() {
    self.accepted = AsyncStream.makeStream()
  }

  fileprivate func acceptStream(_ stream: RPCStream<Inbound, Outbound>) {
    self.accepted.continuation.yield(stream)
  }

  func listen() async throws -> RPCAsyncSequence<RPCStream<Inbound, Outbound>> {
    return RPCAsyncSequence(wrapping: self.accepted.stream)
  }

  func stopListening() {
    self.accepted.continuation.finish()
  }

  func spawnClientTransport(
    throttle: RetryThrottle = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1)
  ) -> TestingClientTransport {
    return TestingClientTransport(server: self, throttle: throttle)
  }
}
