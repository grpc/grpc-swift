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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerInterceptor where Self == RejectAllServerInterceptor {
  static func rejectAll(with error: RPCError) -> Self {
    return RejectAllServerInterceptor(error: error, throw: false)
  }

  static func throwError(_ error: RPCError) -> Self {
    return RejectAllServerInterceptor(error: error, throw: true)
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerInterceptor where Self == RequestCountingServerInterceptor {
  static func requestCounter(_ counter: ManagedAtomic<Int>) -> Self {
    return RequestCountingServerInterceptor(counter: counter)
  }
}

/// Rejects all RPCs with the provided error.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct RejectAllServerInterceptor: ServerInterceptor {
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
    request: ServerRequest.Stream<Input>,
    context: ServerInterceptorContext,
    next: @Sendable (
      ServerRequest.Stream<Input>,
      ServerInterceptorContext
    ) async throws -> ServerResponse.Stream<Output>
  ) async throws -> ServerResponse.Stream<Output> {
    if self.throw {
      throw self.error
    } else {
      return ServerResponse.Stream(error: self.error)
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct RequestCountingServerInterceptor: ServerInterceptor {
  /// The number of requests made.
  let counter: ManagedAtomic<Int>

  init(counter: ManagedAtomic<Int>) {
    self.counter = counter
  }

  func intercept<Input: Sendable, Output: Sendable>(
    request: ServerRequest.Stream<Input>,
    context: ServerInterceptorContext,
    next: @Sendable (
      ServerRequest.Stream<Input>,
      ServerInterceptorContext
    ) async throws -> ServerResponse.Stream<Output>
  ) async throws -> ServerResponse.Stream<Output> {
    self.counter.wrappingIncrement(ordering: .sequentiallyConsistent)
    return try await next(request, context)
  }
}
