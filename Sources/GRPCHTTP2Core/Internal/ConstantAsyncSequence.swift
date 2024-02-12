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

private struct ConstantAsyncSequence<Element: Sendable>: AsyncSequence {
  private let element: Element

  init(element: Element) {
    self.element = element
  }

  func makeAsyncIterator() -> AsyncIterator {
    return AsyncIterator(element: self.element)
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    private let element: Element

    fileprivate init(element: Element) {
      self.element = element
    }

    func next() async throws -> Element? {
      return self.element
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension RPCAsyncSequence {
  static func constant(_ element: Element) -> RPCAsyncSequence<Element> {
    return RPCAsyncSequence(wrapping: ConstantAsyncSequence(element: element))
  }
}
