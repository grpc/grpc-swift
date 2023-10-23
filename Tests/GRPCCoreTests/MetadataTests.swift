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
import Foundation
import GRPCCore
import XCTest

final class MetadataTests: XCTestCase {
  func testAddStringValue() {
    var metadata = Metadata()
    XCTAssertEqual(metadata.count, 0)

    metadata.add(key: "testString", stringValue: "testValue")
    XCTAssertEqual(metadata.count, 1)

    var iterator = metadata[keyForStringValues: "testString"]
    XCTAssertEqual(iterator.next(), "testValue")
    XCTAssertNil(iterator.next())
  }

  func testAddBinaryValue() {
    var metadata = Metadata()
    XCTAssertEqual(metadata.count, 0)

    metadata.add(key: "testBinary-bin", binaryValue: Data("base64encodedString".utf8))
    XCTAssertEqual(metadata.count, 1)

    var iterator = metadata[keyForBinaryValues: "testBinary-bin"]
    XCTAssertEqual(iterator.next(), Data("base64encodedString".utf8))
    XCTAssertNil(iterator.next())
  }

  func testCreateFromDictionaryLiteral() {
    let metadata = Metadata(
      dictionaryLiteral: ("testKey", .string("stringValue")),
      ("testKey-bin", .binary(Data("base64encodedString".utf8)))
    )
    XCTAssertEqual(metadata.count, 2)

    var stringIterator = metadata[keyForStringValues: "testKey"]
    XCTAssertEqual(stringIterator.next(), "stringValue")
    XCTAssertNil(stringIterator.next())

    var binaryIterator = metadata[keyForBinaryValues: "testKey-bin"]
    XCTAssertEqual(binaryIterator.next(), Data("base64encodedString".utf8))
    XCTAssertNil(binaryIterator.next())
  }

  func testReplaceOrAddValue() {
    var metadata = Metadata(
      dictionaryLiteral: ("testKey", .string("value1")),
      ("testKey", .string("value2"))
    )
    XCTAssertEqual(metadata.count, 2)

    var iterator = metadata[keyForStringValues: "testKey"]
    XCTAssertEqual(iterator.next(), "value1")
    XCTAssertEqual(iterator.next(), "value2")
    XCTAssertNil(iterator.next())

    metadata.replaceOrAdd(key: "testKey2", stringValue: "anotherValue")
    XCTAssertEqual(metadata.count, 3)
    iterator = metadata[keyForStringValues: "testKey"]
    XCTAssertEqual(iterator.next(), "value1")
    XCTAssertEqual(iterator.next(), "value2")
    XCTAssertNil(iterator.next())
    iterator = metadata[keyForStringValues: "testKey2"]
    XCTAssertEqual(iterator.next(), "anotherValue")
    XCTAssertNil(iterator.next())

    metadata.replaceOrAdd(key: "testKey", stringValue: "newValue")
    XCTAssertEqual(metadata.count, 2)
    iterator = metadata[keyForStringValues: "testKey"]
    XCTAssertEqual(iterator.next(), "newValue")
    XCTAssertNil(iterator.next())
    iterator = metadata[keyForStringValues: "testKey2"]
    XCTAssertEqual(iterator.next(), "anotherValue")
    XCTAssertNil(iterator.next())
  }

  func testReserveCapacity() {
    var metadata = Metadata()
    XCTAssertEqual(metadata.capacity, 0)

    metadata.reserveCapacity(10)
    XCTAssertEqual(metadata.capacity, 10)
  }

  func testStringIterator() {
    let metadata = Metadata(
      dictionaryLiteral: ("testKey-bin", .string("string1")),
      ("testKey-bin", .binary(.init("data1".utf8))),
      ("testKey-bin", .string("string2")),
      ("testKey-bin", .binary(.init("data2".utf8))),
      ("testKey-bin", .string("string3")),
      ("testKey-bin", .binary(.init("data3".utf8)))
    )
    XCTAssertEqual(metadata.count, 6)

    var stringIterator = metadata[keyForStringValues: "testKey-bin"]
    XCTAssertEqual(stringIterator.next(), "string1")
    XCTAssertEqual(stringIterator.next(), "string2")
    XCTAssertEqual(stringIterator.next(), "string3")
    XCTAssertNil(stringIterator.next())
  }

  func testBinaryIterator() {
    let metadata = Metadata(
      dictionaryLiteral: ("testKey-bin", .string("string1")),
      ("testKey-bin", .binary(.init("data1".utf8))),
      ("testKey-bin", .string("string2")),
      ("testKey-bin", .binary(.init("data2".utf8))),
      ("testKey-bin", .string("string3")),
      ("testKey-bin", .binary(.init("data3".utf8)))
    )
    XCTAssertEqual(metadata.count, 6)

    var binaryIterator = metadata[keyForBinaryValues: "testKey-bin"]
    XCTAssertEqual(binaryIterator.next(), Data("data1".utf8))
    XCTAssertEqual(binaryIterator.next(), Data("data2".utf8))
    XCTAssertEqual(binaryIterator.next(), Data("data3".utf8))
    XCTAssertNil(binaryIterator.next())
  }
}
