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

import EchoModel
import GRPCCore
import GRPCProtobuf
import SwiftProtobuf
import XCTest

final class CodingTests: XCTestCase {
  func testSerializeDeserializeRoundtrip() throws {
    let message = TestMessage.with {
      $0.text = "TestText"
    }

    let serializer = ProtobufSerializer<TestMessage>()
    let deserializer = ProtobufDeserializer<TestMessage>()

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
            The message could not be serialized.
            """
        )
      )
    }
  }

  func testDeserializerError() throws {
    let invalidData = "%%%%%££££".data(using: .utf8)
    let bytes = [UInt8](invalidData!)
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
            The data could not be deserialized into a Message.
            """
        )
      )
    }
  }
}

struct TestMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase {

  var text: String = ""
  var unknownFields = SwiftProtobuf.UnknownStorage()
  static var protoMessageName: String = "Test" + ".ServiceRequest"
  init() {}

  mutating func decodeMessage<D>(decoder: inout D) throws where D: SwiftProtobuf.Decoder {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.text) }()
      default: break
      }
    }
  }

  func traverse<V>(visitor: inout V) throws where V: SwiftProtobuf.Visitor {
    if !self.text.isEmpty {
      try visitor.visitSingularStringField(value: self.text, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func == (lhs: TestMessage, rhs: TestMessage) -> Bool {
    if lhs.text != rhs.text { return false }
    if lhs.unknownFields != rhs.unknownFields { return false }
    return true
  }

  public var isInitialized: Bool {
    if self.text.isEmpty { return false }
    return true
  }
}
