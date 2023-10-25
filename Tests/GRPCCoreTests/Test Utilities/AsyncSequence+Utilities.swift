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

extension AsyncSequence {
  func collect() async throws -> [Element] {
    return try await self.reduce(into: []) { $0.append($1) }
  }
}

#if swift(<5.9)
extension AsyncStream {
  static func makeStream(
    of elementType: Element.Type = Element.self,
    bufferingPolicy limit: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded
  ) -> (stream: AsyncStream<Element>, continuation: AsyncStream<Element>.Continuation) {
    var continuation: AsyncStream<Element>.Continuation!
    let stream = AsyncStream(Element.self, bufferingPolicy: limit) {
      continuation = $0
    }
    return (stream, continuation)
  }
}

extension AsyncThrowingStream {
  static func makeStream(
    of elementType: Element.Type = Element.self,
    throwing failureType: Failure.Type = Failure.self,
    bufferingPolicy limit: AsyncThrowingStream<Element, Failure>.Continuation.BufferingPolicy =
      .unbounded
  ) -> (
    stream: AsyncThrowingStream<Element, Failure>,
    continuation: AsyncThrowingStream<Element, Failure>.Continuation
  ) where Failure == Error {
    var continuation: AsyncThrowingStream<Element, Failure>.Continuation!
    let stream = AsyncThrowingStream(bufferingPolicy: limit) { continuation = $0 }
    return (stream, continuation!)
  }
}
#endif
