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
struct MessageToRPCResponsePartWriter<Serializer: MessageSerializer>: RPCWriterProtocol {
  @usableFromInline
  typealias Element = Serializer.Message

  @usableFromInline
  let base: RPCWriter<RPCResponsePart>
  @usableFromInline
  let serializer: Serializer

  @inlinable
  init(serializer: Serializer, base: some RPCWriterProtocol<RPCResponsePart>) {
    self.serializer = serializer
    self.base = RPCWriter(wrapping: base)
  }

  @inlinable
  func write(contentsOf elements: some Sequence<Serializer.Message>) async throws {
    let requestParts = try elements.map { message -> RPCResponsePart in
      .message(try self.serializer.serialize(message))
    }

    try await self.base.write(contentsOf: requestParts)
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension RPCWriter {
  @inlinable
  static func serializingToRPCResponsePart(
    into writer: some RPCWriterProtocol<RPCResponsePart>,
    with serializer: some MessageSerializer<Element>
  ) -> Self {
    return RPCWriter(wrapping: MessageToRPCResponsePartWriter(serializer: serializer, base: writer))
  }
}
