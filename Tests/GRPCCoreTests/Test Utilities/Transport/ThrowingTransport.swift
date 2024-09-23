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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct ThrowOnStreamCreationTransport: ClientTransport {
  typealias Inbound = RPCAsyncSequence<RPCResponsePart, any Error>
  typealias Outbound = RPCWriter<RPCRequestPart>.Closable

  private let code: RPCError.Code

  init(code: RPCError.Code) {
    self.code = code
  }

  let retryThrottle: RetryThrottle? = RetryThrottle(maxTokens: 10, tokenRatio: 0.1)

  func connect() async throws {
    // no-op
  }

  func beginGracefulShutdown() {
    // no-op
  }

  func config(
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
  func listen(
    streamHandler: (
      _ stream: RPCStream<Inbound, Outbound>,
      _ context: ServerContext
    ) async -> Void
  ) async throws {
    throw RPCError(
      code: .unavailable,
      message: "The '\(type(of: self))' transport is never available."
    )
  }

  func beginGracefulShutdown() {
    // no-op
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct ThrowOnSignalServerTransport: ServerTransport {
  let signal: AsyncStream<Void>

  init(signal: AsyncStream<Void>) {
    self.signal = signal
  }

  func listen(
    streamHandler: (
      _ stream: RPCStream<Inbound, Outbound>,
      _ context: ServerContext
    ) async -> Void
  ) async throws {
    for await _ in self.signal {}

    throw RPCError(
      code: .unavailable,
      message: "The '\(type(of: self))' transport is never available."
    )
  }

  func beginGracefulShutdown() {
    // no-op
  }
}
