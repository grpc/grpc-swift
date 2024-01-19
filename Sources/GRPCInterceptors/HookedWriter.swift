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
import Tracing

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct HookedWriter<Element>: RPCWriterProtocol {
  private let writer: any RPCWriterProtocol<Element>
  private let beforeEachWrite: @Sendable () -> Void
  private let afterEachWrite: @Sendable () -> Void

  init(
    wrapping other: some RPCWriterProtocol<Element>,
    beforeEachWrite: @Sendable @escaping () -> Void,
    afterEachWrite: @Sendable @escaping () -> Void
  ) {
    self.writer = other
    self.beforeEachWrite = beforeEachWrite
    self.afterEachWrite = afterEachWrite
  }

  func write(contentsOf elements: some Sequence<Element>) async throws {
    self.beforeEachWrite()
    try await self.writer.write(contentsOf: elements)
    self.afterEachWrite()
  }
}
