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
import GRPCCore
import XCTest

final class CodingTests: XCTestCase {
  func testJSONRoundtrip() throws {
    // This test just demonstrates that the API is suitable.

    struct Message: Codable, Hashable {
      var foo: String
      var bar: Int
      var baz: Baz

      struct Baz: Codable, Hashable {
        var bazzy: Double
      }
    }

    let message = Message(foo: "foo", bar: 42, baz: .init(bazzy: 3.1415))

    let serializer = JSONSerializer<Message>()
    let deserializer = JSONDeserializer<Message>()

    let bytes = try serializer.serialize(message)
    let roundTrip = try deserializer.deserialize(bytes)
    XCTAssertEqual(roundTrip, message)
  }
}
