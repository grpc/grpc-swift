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

  let retryThrottle = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1)

  func connect(lazily: Bool) async throws {
    // no-op
  }

  func close() {
    // no-op
  }

  func executionConfiguration(
    forMethod descriptor: MethodDescriptor
  ) -> ClientRPCExecutionConfiguration? {
    return nil
  }

  func openStream(
    descriptor: MethodDescriptor
  ) async throws -> RPCStream<Inbound, Outbound> {
    throw RPCError(code: self.code, message: "")
  }
}
