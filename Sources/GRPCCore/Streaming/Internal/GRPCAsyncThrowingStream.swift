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

// This exists to provide a version of 'AsyncThrowingStream' which is constrained to 'Sendable'
// elements. This is required in order for the continuation to be compatible with
// 'RPCWriterProtocol'. (Adding a constrained conformance to 'RPCWriterProtocol' on
// 'AsyncThrowingStream.Continuation' isn't possible because 'Sendable' is a marker protocol.)

package struct GRPCAsyncThrowingStream<Element: Sendable>: AsyncSequence, Sendable {
  package typealias Element = Element
  package typealias Failure = any Error

  private let base: AsyncThrowingStream<Element, any Error>

  package static func makeStream(
    of: Element.Type = Element.self
  ) -> (stream: Self, continuation: Self.Continuation) {
    let base = AsyncThrowingStream.makeStream(of: Element.self)
    let stream = GRPCAsyncThrowingStream(base: base.stream)
    let continuation = GRPCAsyncThrowingStream.Continuation(base: base.continuation)
    return (stream, continuation)
  }

  fileprivate init(base: AsyncThrowingStream<Element, any Error>) {
    self.base = base
  }

  package struct Continuation: Sendable {
    private let base: AsyncThrowingStream<Element, any Error>.Continuation

    fileprivate init(base: AsyncThrowingStream<Element, any Error>.Continuation) {
      self.base = base
    }

    func yield(_ value: Element) {
      self.base.yield(value)
    }

    func finish(throwing error: (any Error)? = nil) {
      self.base.finish(throwing: error)
    }
  }

  package func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(base: self.base.makeAsyncIterator())
  }

  package struct AsyncIterator: AsyncIteratorProtocol {
    private var base: AsyncThrowingStream<Element, any Error>.AsyncIterator

    fileprivate init(base: AsyncThrowingStream<Element, any Error>.AsyncIterator) {
      self.base = base
    }

    package mutating func next() async throws(any Error) -> Element? {
      try await self.next(isolation: nil)
    }

    package mutating func next(
      isolation actor: isolated (any Actor)?
    ) async throws(any Error) -> Element? {
      try await self.base.next(isolation: `actor`)
    }
  }
}

extension GRPCAsyncThrowingStream.Continuation: RPCWriterProtocol {
  package func write(_ element: Element) async throws {
    self.yield(element)
  }

  package func write(contentsOf elements: some Sequence<Element>) async throws {
    for element in elements {
      self.yield(element)
    }
  }
}

extension GRPCAsyncThrowingStream.Continuation: ClosableRPCWriterProtocol {
  package func finish() async {
    self.finish(throwing: nil)
  }

  package func finish(throwing error: any Error) async {
    self.finish(throwing: .some(error))
  }
}
