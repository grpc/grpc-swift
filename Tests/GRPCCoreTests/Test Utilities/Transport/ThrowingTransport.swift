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
struct ThrowOnStreamCreationTransport: ClientTransport {
  typealias Inbound = RPCAsyncSequence<RPCResponsePart>
  typealias Outbound = RPCWriter<RPCRequestPart>.Closable

  private let code: RPCError.Code

  init(code: RPCError.Code) {
    self.code = code
  }

  let retryThrottle: RetryThrottle? = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1)

  func connect() async throws {
    // no-op
  }

  func close() {
    // no-op
  }

  func configuration(
    forMethod descriptor: MethodDescriptor
  ) -> MethodConfig? {
    return nil
  }

  func withStream<T>(
    descriptor: MethodDescriptor,
    options: CallOptions,
    _ closure: (RPCStream<Inbound, Outbound>) async throws -> T
  ) async throws -> T {
    throw RPCError(code: self.code, message: "")
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct ThrowOnRunServerTransport: ServerTransport {
  var events: NoThrowRPCAsyncSequence<ServerTransportEvent> {
    NoThrowRPCAsyncSequence(
      wrapping: AsyncStream {
        .failedToStartListening(
          RPCError(
            code: .unavailable,
            message: "The '\(type(of: self))' transport is never available."
          )
        )
      }
    )
  }

  func listen() async {
    // no-op
  }

  func stopListening() {
    // no-op
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct ThrowOnSignalServerTransport: ServerTransport {
  let signal: AsyncStream<Void>
  private let eventStream: AsyncStream<ServerTransportEvent>
  private let eventStreamContinuation: AsyncStream<ServerTransportEvent>.Continuation

  var events: NoThrowRPCAsyncSequence<ServerTransportEvent> {
    NoThrowRPCAsyncSequence(wrapping: self.eventStream)
  }

  init(signal: AsyncStream<Void>) {
    self.signal = signal
    (self.eventStream, self.eventStreamContinuation) = AsyncStream.makeStream()
  }

  func listen() async {
    for await _ in self.signal {}
    let error = RPCError(
      code: .unavailable,
      message: "The '\(type(of: self))' transport is never available."
    )
    self.eventStreamContinuation.yield(.failedToStartListening(error))
    self.eventStreamContinuation.finish()
  }

  func stopListening() {
    // no-op
  }
}
