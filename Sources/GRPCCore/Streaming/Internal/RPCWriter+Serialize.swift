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
@available(gRPCSwift 2.0, *)
struct SerializingRPCWriter<
  Base: RPCWriterProtocol<Bytes>,
  Bytes: GRPCContiguousBytes,
  Serializer: MessageSerializer
>: RPCWriterProtocol where Serializer.Message: Sendable {
  @usableFromInline
  typealias Element = Serializer.Message

  @usableFromInline
  let base: Base
  @usableFromInline
  let serializer: Serializer

  @inlinable
  init(serializer: Serializer, base: Base) {
    self.serializer = serializer
    self.base = base
  }

  @inlinable
  func write(_ element: Element) async throws {
    try await self.base.write(self.serializer.serialize(element))
  }

  @inlinable
  func write(contentsOf elements: some Sequence<Serializer.Message>) async throws {
    let requestParts = try elements.map { message in
      try self.serializer.serialize(message) as Bytes
    }

    try await self.base.write(contentsOf: requestParts)
  }
}

@available(gRPCSwift 2.0, *)
extension RPCWriter {
  @inlinable
  static func serializing(
    into writer: some RPCWriterProtocol<[UInt8]>,
    with serializer: some MessageSerializer<Element>
  ) -> Self {
    return RPCWriter(wrapping: SerializingRPCWriter(serializer: serializer, base: writer))
  }
}
