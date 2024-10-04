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

@usableFromInline
struct MapRPCWriter<
  Value: Sendable,
  Mapped: Sendable,
  Base: RPCWriterProtocol<Mapped>
>: RPCWriterProtocol {
  @usableFromInline
  typealias Element = Value

  @usableFromInline
  let base: Base
  @usableFromInline
  let transform: @Sendable (Value) throws -> Mapped

  @inlinable
  init(base: Base, transform: @escaping @Sendable (Value) throws -> Mapped) {
    self.base = base
    self.transform = transform
  }

  @inlinable
  func write(_ element: Element) async throws {
    try await self.base.write(self.transform(element))
  }

  @inlinable
  func write(contentsOf elements: some Sequence<Value>) async throws {
    let transformed = try elements.lazy.map { try self.transform($0) }
    try await self.base.write(contentsOf: transformed)
  }
}

extension RPCWriter {
  @inlinable
  static func map<Mapped>(
    into writer: some RPCWriterProtocol<Mapped>,
    transform: @Sendable @escaping (Element) throws -> Mapped
  ) -> Self {
    let mapper = MapRPCWriter(base: writer, transform: transform)
    return RPCWriter(wrapping: mapper)
  }
}
