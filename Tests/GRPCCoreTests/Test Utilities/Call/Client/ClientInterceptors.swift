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

import GRPCCore

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ClientInterceptor where Self == RejectAllClientInterceptor {
  static func rejectAll(with error: RPCError) -> Self {
    return RejectAllClientInterceptor(error: error, throw: false)
  }

  static func throwError(_ error: RPCError) -> Self {
    return RejectAllClientInterceptor(error: error, throw: true)
  }

}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ClientInterceptor where Self == RequestCountingClientInterceptor {
  static func requestCounter(_ counter: AtomicCounter) -> Self {
    return RequestCountingClientInterceptor(counter: counter)
  }
}

/// Rejects all RPCs with the provided error.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
    context: ClientContext,
    next: (
      ClientRequest.Stream<Input>,
      ClientContext
    ) async throws -> ClientResponse.Stream<Output>
  ) async throws -> ClientResponse.Stream<Output> {
    if self.throw {
      throw self.error
    } else {
      return ClientResponse.Stream(error: self.error)
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct RequestCountingClientInterceptor: ClientInterceptor {
  /// The number of requests made.
  let counter: AtomicCounter

  init(counter: AtomicCounter) {
    self.counter = counter
  }

  func intercept<Input: Sendable, Output: Sendable>(
    request: ClientRequest.Stream<Input>,
    context: ClientContext,
    next: (
      ClientRequest.Stream<Input>,
      ClientContext
    ) async throws -> ClientResponse.Stream<Output>
  ) async throws -> ClientResponse.Stream<Output> {
    self.counter.increment()
    return try await next(request, context)
  }
}
