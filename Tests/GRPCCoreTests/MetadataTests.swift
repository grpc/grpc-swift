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

final class MetadataTests: XCTestCase {
  func testAddStringValue() {
    var metadata = Metadata()
    XCTAssertTrue(metadata.isEmpty)

    metadata.addString("testValue", forKey: "testString")
    XCTAssertEqual(metadata.count, 1)

    let sequence = metadata[stringValues: "testString"]
    var iterator = sequence.makeIterator()
    XCTAssertEqual(iterator.next(), "testValue")
    XCTAssertNil(iterator.next())
  }

  func testAddBinaryValue() {
    var metadata = Metadata()
    XCTAssertTrue(metadata.isEmpty)

    metadata.addBinary(Array("base64encodedString".utf8), forKey: "testBinary-bin")
    XCTAssertEqual(metadata.count, 1)

    let sequence = metadata[binaryValues: "testBinary-bin"]
    var iterator = sequence.makeIterator()
    XCTAssertEqual(iterator.next(), Array("base64encodedString".utf8))
    XCTAssertNil(iterator.next())
  }

  func testCreateFromDictionaryLiteral() {
    let metadata: Metadata = [
      "testKey": "stringValue",
      "testKey-bin": .binary(Array("base64encodedString".utf8)),
    ]
    XCTAssertEqual(metadata.count, 2)

    let stringSequence = metadata[stringValues: "testKey"]
    var stringIterator = stringSequence.makeIterator()
    XCTAssertEqual(stringIterator.next(), "stringValue")
    XCTAssertNil(stringIterator.next())

    let binarySequence = metadata[binaryValues: "testKey-bin"]
    var binaryIterator = binarySequence.makeIterator()
    XCTAssertEqual(binaryIterator.next(), Array("base64encodedString".utf8))
    XCTAssertNil(binaryIterator.next())
  }

  func testReplaceOrAddValue() {
    var metadata: Metadata = [
      "testKey": "value1",
      "testKey": "value2",
    ]
    XCTAssertEqual(metadata.count, 2)

    var sequence = metadata[stringValues: "testKey"]
    var iterator = sequence.makeIterator()
    XCTAssertEqual(iterator.next(), "value1")
    XCTAssertEqual(iterator.next(), "value2")
    XCTAssertNil(iterator.next())

    metadata.replaceOrAddString("anotherValue", forKey: "testKey2")
    XCTAssertEqual(metadata.count, 3)
    sequence = metadata[stringValues: "testKey"]
    iterator = sequence.makeIterator()
    XCTAssertEqual(iterator.next(), "value1")
    XCTAssertEqual(iterator.next(), "value2")
    XCTAssertNil(iterator.next())
    sequence = metadata[stringValues: "testKey2"]
    iterator = sequence.makeIterator()
    XCTAssertEqual(iterator.next(), "anotherValue")
    XCTAssertNil(iterator.next())

    metadata.replaceOrAddString("newValue", forKey: "testKey")
    XCTAssertEqual(metadata.count, 2)
    sequence = metadata[stringValues: "testKey"]
    iterator = sequence.makeIterator()
    XCTAssertEqual(iterator.next(), "newValue")
    XCTAssertNil(iterator.next())
    sequence = metadata[stringValues: "testKey2"]
    iterator = sequence.makeIterator()
    XCTAssertEqual(iterator.next(), "anotherValue")
    XCTAssertNil(iterator.next())
  }

  func testReserveCapacity() {
    var metadata = Metadata()
    XCTAssertEqual(metadata.capacity, 0)

    metadata.reserveCapacity(10)
    XCTAssertEqual(metadata.capacity, 10)
  }

  func testValuesIteration() {
    let metadata: Metadata = [
      "testKey-bin": "string1",
      "testKey-bin": .binary(.init("data1".utf8)),
      "testKey-bin": "string2",
      "testKey-bin": .binary(.init("data2".utf8)),
      "testKey-bin": "string3",
      "testKey-bin": .binary(.init("data3".utf8)),
    ]
    XCTAssertEqual(metadata.count, 6)

    let sequence = metadata["testKey-bin"]
    var iterator = sequence.makeIterator()
    XCTAssertEqual(iterator.next(), .string("string1"))
    XCTAssertEqual(iterator.next(), .binary(.init("data1".utf8)))
    XCTAssertEqual(iterator.next(), .string("string2"))
    XCTAssertEqual(iterator.next(), .binary(.init("data2".utf8)))
    XCTAssertEqual(iterator.next(), .string("string3"))
    XCTAssertEqual(iterator.next(), .binary(.init("data3".utf8)))
    XCTAssertNil(iterator.next())
  }

  func testStringValuesIteration() {
    let metadata: Metadata = [
      "testKey-bin": "string1",
      "testKey-bin": .binary(.init("data1".utf8)),
      "testKey-bin": "string2",
      "testKey-bin": .binary(.init("data2".utf8)),
      "testKey-bin": "string3",
      "testKey-bin": .binary(.init("data3".utf8)),
    ]
    XCTAssertEqual(metadata.count, 6)

    let stringSequence = metadata[stringValues: "testKey-bin"]
    var stringIterator = stringSequence.makeIterator()
    XCTAssertEqual(stringIterator.next(), "string1")
    XCTAssertEqual(stringIterator.next(), "string2")
    XCTAssertEqual(stringIterator.next(), "string3")
    XCTAssertNil(stringIterator.next())
  }

  func testBinaryValuesIteration_InvalidBase64EncodedStrings() {
    let metadata: Metadata = [
      "testKey-bin": "invalidBase64-1",
      "testKey-bin": .binary(.init("data1".utf8)),
      "testKey-bin": "invalidBase64-2",
      "testKey-bin": .binary(.init("data2".utf8)),
      "testKey-bin": "invalidBase64-3",
      "testKey-bin": .binary(.init("data3".utf8)),
    ]
    XCTAssertEqual(metadata.count, 6)

    let binarySequence = metadata[binaryValues: "testKey-bin"]
    var binaryIterator = binarySequence.makeIterator()
    XCTAssertEqual(binaryIterator.next(), Array("data1".utf8))
    XCTAssertEqual(binaryIterator.next(), Array("data2".utf8))
    XCTAssertEqual(binaryIterator.next(), Array("data3".utf8))
    XCTAssertNil(binaryIterator.next())
  }

  func testBinaryValuesIteration_ValidBase64EncodedStrings() {
    let metadata: Metadata = [
      "testKey-bin": "c3RyaW5nMQ==",
      "testKey-bin": .binary(.init("data1".utf8)),
      "testKey-bin": "c3RyaW5nMg==",
      "testKey-bin": .binary(.init("data2".utf8)),
      "testKey-bin": "c3RyaW5nMw==",
      "testKey-bin": .binary(.init("data3".utf8)),
    ]
    XCTAssertEqual(metadata.count, 6)

    let binarySequence = metadata[binaryValues: "testKey-bin"]
    var binaryIterator = binarySequence.makeIterator()
    XCTAssertEqual(binaryIterator.next(), Array("string1".utf8))
    XCTAssertEqual(binaryIterator.next(), Array("data1".utf8))
    XCTAssertEqual(binaryIterator.next(), Array("string2".utf8))
    XCTAssertEqual(binaryIterator.next(), Array("data2".utf8))
    XCTAssertEqual(binaryIterator.next(), Array("string3".utf8))
    XCTAssertEqual(binaryIterator.next(), Array("data3".utf8))
    XCTAssertNil(binaryIterator.next())
  }

  func testKeysAreCaseInsensitive() {
    let metadata: Metadata = [
      "testkey1": "value1",
      "TESTKEY2": "value2",
    ]
    XCTAssertEqual(metadata.count, 2)

    var stringSequence = metadata[stringValues: "TESTKEY1"]
    var stringIterator = stringSequence.makeIterator()
    XCTAssertEqual(stringIterator.next(), "value1")
    XCTAssertNil(stringIterator.next())

    stringSequence = metadata[stringValues: "testkey2"]
    stringIterator = stringSequence.makeIterator()
    XCTAssertEqual(stringIterator.next(), "value2")
    XCTAssertNil(stringIterator.next())
  }
}
