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
import Testing

@Suite("Metadata")
struct MetadataTests {
  @Test("Initialize from Sequence")
  func initFromSequence() {
    let elements: [Metadata.Element] = [
      (key: "key1", value: "value1"),
      (key: "key2", value: "value2"),
      (key: "key3", value: "value3"),
    ]

    let metadata = Metadata(elements)
    let expected: Metadata = ["key1": "value1", "key2": "value2", "key3": "value3"]
    #expect(metadata == expected)
  }

  @Test("Add string Value")
  func addStringValue() {
    var metadata = Metadata()
    #expect(metadata.isEmpty)

    metadata.addString("testValue", forKey: "testString")
    #expect(metadata.count == 1)

    let sequence = metadata[stringValues: "testString"]
    var iterator = sequence.makeIterator()
    #expect(iterator.next() == "testValue")
    #expect(iterator.next() == nil)
  }

  @Test("Add binary value")
  func addBinaryValue() {
    var metadata = Metadata()
    #expect(metadata.isEmpty)

    metadata.addBinary(Array("base64encodedString".utf8), forKey: "testBinary-bin")
    #expect(metadata.count == 1)

    let sequence = metadata[binaryValues: "testBinary-bin"]
    var iterator = sequence.makeIterator()
    #expect(iterator.next() == Array("base64encodedString".utf8))
    #expect(iterator.next() == nil)
  }

  @Test("Initialize from dictionary literal")
  func initFromDictionaryLiteral() {
    let metadata: Metadata = [
      "testKey": "stringValue",
      "testKey-bin": .binary(Array("base64encodedString".utf8)),
    ]
    #expect(metadata.count == 2)

    let stringSequence = metadata[stringValues: "testKey"]
    var stringIterator = stringSequence.makeIterator()
    #expect(stringIterator.next() == "stringValue")
    #expect(stringIterator.next() == nil)

    let binarySequence = metadata[binaryValues: "testKey-bin"]
    var binaryIterator = binarySequence.makeIterator()
    #expect(binaryIterator.next() == Array("base64encodedString".utf8))
    #expect(binaryIterator.next() == nil)
  }

  @Suite("Replace or add value")
  struct ReplaceOrAdd {
    @Suite("String")
    struct StringValues {
      var metadata: Metadata = [
        "key1": "value1",
        "key1": "value2",
      ]

      @Test("Add different key")
      mutating func addNewKey() async throws {
        self.metadata.replaceOrAddString("value3", forKey: "key2")
        #expect(Array(self.metadata[stringValues: "key1"]) == ["value1", "value2"])
        #expect(Array(self.metadata[stringValues: "key2"]) == ["value3"])
        #expect(self.metadata.count == 3)
      }

      @Test("Replace values for existing key")
      mutating func replaceValues() async throws {
        self.metadata.replaceOrAddString("value3", forKey: "key1")
        #expect(Array(self.metadata[stringValues: "key1"]) == ["value3"])
        #expect(self.metadata.count == 1)
      }
    }

    @Suite("Binary")
    struct BinaryValues {
      var metadata: Metadata = [
        "key1-bin": [0],
        "key1-bin": [1],
      ]

      @Test("Add different key")
      mutating func addNewKey() async throws {
        self.metadata.replaceOrAddBinary([2], forKey: "key2-bin")
        #expect(Array(self.metadata[binaryValues: "key1-bin"]) == [[0], [1]])
        #expect(Array(self.metadata[binaryValues: "key2-bin"]) == [[2]])
        #expect(self.metadata.count == 3)
      }

      @Test("Replace values for existing key")
      mutating func replaceValues() async throws {
        self.metadata.replaceOrAddBinary([2], forKey: "key1-bin")
        #expect(Array(self.metadata[binaryValues: "key1-bin"]) == [[2]])
        #expect(self.metadata.count == 1)
      }
    }
  }

  @Test("Reserve more capacity increases capacity")
  func reserveMoreCapacity() {
    var metadata = Metadata()
    #expect(metadata.capacity == 0)

    metadata.reserveCapacity(10)
    #expect(metadata.capacity == 10)
  }

  @Test("Reserve less capacity doesn't reduce capacity")
  func reserveCapacity() {
    var metadata = Metadata()
    #expect(metadata.capacity == 0)
    metadata.reserveCapacity(10)
    #expect(metadata.capacity == 10)
    metadata.reserveCapacity(0)
    #expect(metadata.capacity == 10)
  }

  @Test("Iterate over all values for a key")
  func iterateOverValuesForKey() {
    let metadata: Metadata = [
      "key-bin": "1",
      "key-bin": [1],
      "key-bin": "2",
      "key-bin": [2],
      "key-bin": "3",
      "key-bin": [3],
    ]

    #expect(Array(metadata["key-bin"]) == ["1", [1], "2", [2], "3", [3]])
  }

  @Test("Iterate over string values for a key")
  func iterateOverStringsForKey() {
    let metadata: Metadata = [
      "key-bin": "1",
      "key-bin": [1],
      "key-bin": "2",
      "key-bin": [2],
      "key-bin": "3",
      "key-bin": [3],
    ]

    #expect(Array(metadata[stringValues: "key-bin"]) == ["1", "2", "3"])
  }

  @Test("Iterate over binary values for a key")
  func iterateOverBinaryForKey() {
    let metadata: Metadata = [
      "key-bin": "1",
      "key-bin": [1],
      "key-bin": "2",
      "key-bin": [2],
      "key-bin": "3",
      "key-bin": [3],
    ]

    #expect(Array(metadata[binaryValues: "key-bin"]) == [[1], [2], [3]])
  }

  @Test("Iterate over base64 encoded binary values for a key")
  func iterateOverBase64BinaryEncodedValuesForKey() {
    let metadata: Metadata = [
      "key-bin": "c3RyaW5nMQ==",
      "key-bin": .binary(.init("data1".utf8)),
      "key-bin": "c3RyaW5nMg==",
      "key-bin": .binary(.init("data2".utf8)),
      "key-bin": "c3RyaW5nMw==",
      "key-bin": .binary(.init("data3".utf8)),
    ]

    let expected: [[UInt8]] = [
      Array("string1".utf8),
      Array("data1".utf8),
      Array("string2".utf8),
      Array("data2".utf8),
      Array("string3".utf8),
      Array("data3".utf8),
    ]

    #expect(Array(metadata[binaryValues: "key-bin"]) == expected)
  }

  @Test("Subscripts are case-insensitive")
  func subscriptIsCaseInsensitive() {
    let metadata: Metadata = [
      "key1": "value1",
      "KEY2": "value2",
    ]

    #expect(Array(metadata[stringValues: "key1"]) == ["value1"])
    #expect(Array(metadata[stringValues: "KEY1"]) == ["value1"])

    #expect(Array(metadata[stringValues: "key2"]) == ["value2"])
    #expect(Array(metadata[stringValues: "KEY2"]) == ["value2"])
  }

  @Suite("Remove all")
  struct RemoveAll {
    var metadata: Metadata = [
      "key1": "value1",
      "key2": "value2",
      "key3": "value1",
    ]

    @Test("Where value matches")
    mutating func removeAllWhereValueMatches() async throws {
      self.metadata.removeAll { _, value in
        value == "value1"
      }

      #expect(self.metadata == ["key2": "value2"])
    }

    @Test("Where key matches")
    mutating func removeAllWhereKeyMatches() async throws {
      self.metadata.removeAll { key, _ in
        key == "key2"
      }

      #expect(self.metadata == ["key1": "value1", "key3": "value1"])
    }
  }
}
