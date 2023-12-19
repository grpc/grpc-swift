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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension RPCAsyncSequence {
  static func elements(_ elements: Element...) -> Self {
    return .elements(elements)
  }

  static func elements(_ elements: [Element]) -> Self {
    let stream = AsyncStream<Element> {
      for element in elements {
        $0.yield(element)
      }
      $0.finish()
    }
    return RPCAsyncSequence(wrapping: stream)
  }
}
