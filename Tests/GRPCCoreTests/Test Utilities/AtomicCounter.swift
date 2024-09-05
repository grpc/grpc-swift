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

import Synchronization

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class AtomicCounter: Sendable {
  private let counter: Atomic<Int>

  init(_ initialValue: Int = 0) {
    self.counter = Atomic(initialValue)
  }

  var value: Int {
    self.counter.load(ordering: .sequentiallyConsistent)
  }

  @discardableResult
  func increment() -> (oldValue: Int, newValue: Int) {
    self.counter.add(1, ordering: .sequentiallyConsistent)
  }
}
