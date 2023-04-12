/*
 * Copyright 2022, gRPC Authors All rights reserved.
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
import DequeModule
import NIOCore

@usableFromInline
internal struct GRPCAsyncWriterSinkDelegate<Element: Sendable>: NIOAsyncWriterSinkDelegate {
  @usableFromInline
  let _didYield: (@Sendable (Deque<Element>) -> Void)?

  @usableFromInline
  let _didTerminate: (@Sendable (Error?) -> Void)?

  @inlinable
  init(
    didYield: (@Sendable (Deque<Element>) -> Void)? = nil,
    didTerminate: (@Sendable (Error?) -> Void)? = nil
  ) {
    self._didYield = didYield
    self._didTerminate = didTerminate
  }

  @inlinable
  func didYield(contentsOf sequence: Deque<Element>) {
    self._didYield?(sequence)
  }

  @inlinable
  func didTerminate(error: Error?) {
    self._didTerminate?(error)
  }
}
