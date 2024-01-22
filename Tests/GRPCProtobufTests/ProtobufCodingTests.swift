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
import GRPCProtobuf
import SwiftProtobuf
import XCTest

final class ProtobufCodingTests: XCTestCase {
  func testSerializeDeserializeRoundtrip() throws {
    let message = Google_Protobuf_Timestamp.with {
      $0.seconds = 4
    }

    let serializer = ProtobufSerializer<Google_Protobuf_Timestamp>()
    let deserializer = ProtobufDeserializer<Google_Protobuf_Timestamp>()

    let bytes = try serializer.serialize(message)
    let roundTrip = try deserializer.deserialize(bytes)
    XCTAssertEqual(roundTrip, message)
  }

  func testSerializerError() throws {
    let message = TestMessage()
    let serializer = ProtobufSerializer<TestMessage>()

    XCTAssertThrowsError(
      try serializer.serialize(message)
    ) { error in
      XCTAssertEqual(
        error as? RPCError,
        RPCError(
          code: .invalidArgument,
          message:
            """
            Can't serialize message of type TestMessage.
            """
        )
      )
    }
  }

  func testDeserializerError() throws {
    let bytes = Array("%%%%%££££".utf8)
    let deserializer = ProtobufDeserializer<TestMessage>()
    XCTAssertThrowsError(
      try deserializer.deserialize(bytes)
    ) { error in
      XCTAssertEqual(
        error as? RPCError,
        RPCError(
          code: .invalidArgument,
          message:
            """
            Can't deserialize to message of type TestMessage
            """
        )
      )
    }
  }
}

struct TestMessage: SwiftProtobuf.Message {
  var text: String = ""
  var unknownFields = SwiftProtobuf.UnknownStorage()
  static var protoMessageName: String = "Test" + ".ServiceRequest"
  init() {}

  mutating func decodeMessage<D>(decoder: inout D) throws where D: SwiftProtobuf.Decoder {
    throw RPCError(code: .internalError, message: "Decoding error")
  }

  func traverse<V>(visitor: inout V) throws where V: SwiftProtobuf.Visitor {
    throw RPCError(code: .internalError, message: "Traversing error")
  }

  public var isInitialized: Bool {
    if self.text.isEmpty { return false }
    return true
  }

  func isEqualTo(message: SwiftProtobuf.Message) -> Bool {
    return false
  }
}
