/*
 * Copyright 2024, gRPC Authors All rights reserved.
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
import GRPCHTTP2Core

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension NameResolver {
  static func `static`(
    endpoints: [Endpoint],
    serviceConfig: ServiceConfig? = nil
  ) -> Self {
    let result = NameResolutionResult(
      endpoints: endpoints,
      serviceConfig: serviceConfig.map { .success($0) }
    )

    return NameResolver(
      names: RPCAsyncSequence(wrapping: ConstantAsyncSequence(element: result)),
      updateMode: .pull
    )
  }

  static func `dynamic`(
    updateMode: UpdateMode
  ) -> (Self, AsyncThrowingStream<NameResolutionResult, any Error>.Continuation) {
    let (stream, continuation) = AsyncThrowingStream.makeStream(of: NameResolutionResult.self)
    let resolver = NameResolver(names: RPCAsyncSequence(wrapping: stream), updateMode: updateMode)
    return (resolver, continuation)
  }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
struct ConstantAsyncSequence<Element>: AsyncSequence {
  private let result: Result<Element, Error>

  init(element: Element) {
    self.result = .success(element)
  }

  init(error: any Error) {
    self.result = .failure(error)
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(result: self.result)
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    private let result: Result<Element, Error>

    fileprivate init(result: Result<Element, Error>) {
      self.result = result
    }

    func next() async throws -> Element? {
      try self.result.get()
    }
  }

}
