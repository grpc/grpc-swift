/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
@testable import GRPC
import NIO
import XCTest

class GRPCServerCodecHandlerTests: GRPCTestCase {
  struct BlowUpError: Error {}

  struct BlowUpSerializer: MessageSerializer {
    typealias Input = Any

    func serialize(_ input: Any, allocator: ByteBufferAllocator) throws -> ByteBuffer {
      throw BlowUpError()
    }
  }

  struct BlowUpDeserializer: MessageDeserializer {
    typealias Output = Any

    func deserialize(byteBuffer: ByteBuffer) throws -> Any {
      throw BlowUpError()
    }
  }

  func testSerializationFailure() throws {
    let handler = GRPCServerCodecHandler(
      serializer: BlowUpSerializer(),
      deserializer: BlowUpDeserializer()
    )
    let channel = EmbeddedChannel(handler: handler)
    XCTAssertThrowsError(try channel.writeInbound(_RawGRPCServerRequestPart.message(ByteBuffer())))
    XCTAssertNil(try channel.readInbound(as: Any.self))
  }

  func testDeserializationFailure() throws {
    let handler = GRPCServerCodecHandler(
      serializer: BlowUpSerializer(),
      deserializer: BlowUpDeserializer()
    )
    let channel = EmbeddedChannel(handler: handler)
    XCTAssertThrowsError(
      try channel
        .writeOutbound(_GRPCServerResponsePart<Any>.message(.init(ByteBuffer(), compressed: false)))
    )
    XCTAssertNil(try channel.readOutbound(as: Any.self))
  }
}
