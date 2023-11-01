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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
struct MapRPCWriter<Value, Mapped>: RPCWriterProtocol {
  @usableFromInline
  typealias Element = Value

  @usableFromInline
  let base: RPCWriter<Mapped>
  @usableFromInline
  let transform: @Sendable (Value) -> Mapped

  @inlinable
  init(base: some RPCWriterProtocol<Mapped>, transform: @escaping @Sendable (Value) -> Mapped) {
    self.base = RPCWriter(wrapping: base)
    self.transform = transform
  }

  @inlinable
  func write(contentsOf elements: some Sequence<Value>) async throws {
    let transformed = elements.lazy.map { self.transform($0) }
    try await self.base.write(contentsOf: transformed)
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension RPCWriter {
  @inlinable
  static func map<Mapped>(
    into writer: some RPCWriterProtocol<Mapped>,
    transform: @Sendable @escaping (Element) -> Mapped
  ) -> Self {
    let mapper = MapRPCWriter(base: writer, transform: transform)
    return RPCWriter(wrapping: mapper)
  }
}
