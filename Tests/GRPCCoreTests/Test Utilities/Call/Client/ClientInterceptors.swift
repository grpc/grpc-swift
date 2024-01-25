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
import GRPCCore

extension ClientInterceptor where Self == RejectAllClientInterceptor {
  static func rejectAll(with error: RPCError) -> Self {
    return RejectAllClientInterceptor(error: error, throw: false)
  }

  static func throwError(_ error: RPCError) -> Self {
    return RejectAllClientInterceptor(error: error, throw: true)
  }

}

extension ClientInterceptor where Self == RequestCountingClientInterceptor {
  static func requestCounter(_ counter: ManagedAtomic<Int>) -> Self {
    return RequestCountingClientInterceptor(counter: counter)
  }
}

/// Rejects all RPCs with the provided error.
struct RejectAllClientInterceptor: ClientInterceptor {
  /// The error to reject all RPCs with.
  let error: RPCError
  /// Whether the error should be thrown. If `false` then the request is rejected with the error
  /// instead.
  let `throw`: Bool

  init(error: RPCError, throw: Bool = false) {
    self.error = error
    self.`throw` = `throw`
  }

  func intercept<Input: Sendable, Output: Sendable>(
    request: ClientRequest.Stream<Input>,
    context: ClientInterceptorContext,
    next: @Sendable (
      ClientRequest.Stream<Input>,
      ClientInterceptorContext
    ) async throws -> ClientResponse.Stream<Output>
  ) async throws -> ClientResponse.Stream<Output> {
    if self.throw {
      throw self.error
    } else {
      return ClientResponse.Stream(error: self.error)
    }
  }
}

struct RequestCountingClientInterceptor: ClientInterceptor {
  /// The number of requests made.
  let counter: ManagedAtomic<Int>

  init(counter: ManagedAtomic<Int>) {
    self.counter = counter
  }

  func intercept<Input: Sendable, Output: Sendable>(
    request: ClientRequest.Stream<Input>,
    context: ClientInterceptorContext,
    next: @Sendable (
      ClientRequest.Stream<Input>,
      ClientInterceptorContext
    ) async throws -> ClientResponse.Stream<Output>
  ) async throws -> ClientResponse.Stream<Output> {
    self.counter.wrappingIncrement(ordering: .sequentiallyConsistent)
    return try await next(request, context)
  }
}
