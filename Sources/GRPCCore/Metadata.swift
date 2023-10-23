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

/// A collection of metadata key-value pairs, found in RPC streams.
/// A key can have multiple values associated to it.
/// Values can be either strings or binary data, in the form of `Data`.
/// - Note: Binary values must have keys ending in `-bin`, and this will be checked when adding pairs.
public struct Metadata: Sendable, Hashable {

  /// A metadata value. It can either be a simple string, or binary data.
  public enum MetadataValue: Sendable, Hashable {
    case string(String)
    case binary(Data)
  }

  /// A metadata key-value pair.
  public struct MetadataKeyValue: Sendable, Hashable {
    internal let key: String
    internal let value: MetadataValue

    /// Constructor for a metadata key-value pair.
    /// - Parameters:
    ///   - key: The key for the key-value pair.
    ///   - value: The value to be associated to the given key. If it's a binary value, then the associated
    ///   key must end in `-bin`, otherwise, this method will produce an assertion failure.
    init(key: String, value: MetadataValue) {
      if case .binary = value {
        assert(key.hasSuffix("-bin"), "Keys for binary values must end in -bin")
      }
      self.key = key
      self.value = value
    }
  }

  private let lockedElements: LockedValueBox<[MetadataKeyValue]>
  private var elements: [MetadataKeyValue] {
    get {
      self.lockedElements.withLockedValue { $0 }
    }
    set {
      self.lockedElements.withLockedValue { $0 = newValue }
    }
  }

  /// The Metadata collection's capacity.
  public var capacity: Int {
    self.elements.capacity
  }

  /// Initialize an empty Metadata collection.
  public init() {
    self.lockedElements = .init([])
  }

  public static func == (lhs: Metadata, rhs: Metadata) -> Bool {
    lhs.elements == rhs.elements
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.elements)
  }

  /// Reserve the specified minimum capacity in the collection.
  /// - Parameter minimumCapacity: The minimum capacity to reserve in the collection.
  public mutating func reserveCapacity(_ minimumCapacity: Int) {
    self.elements.reserveCapacity(minimumCapacity)
  }

  /// Add a new key-value pair, where the value is a string.
  /// - Parameters:
  ///   - key: The key to be associated with the given value.
  ///   - stringValue: The string value to be associated with the given key.
  public mutating func add(key: String, stringValue: String) {
    self.add(key: key, value: .string(stringValue))
  }

  /// Add a new key-value pair, where the value is binary data, in the form of `Data`.
  /// - Parameters:
  ///   - key: The key to be associated with the given value. Must end in `-bin`.
  ///   - binaryValue: The `Data` to be associated with the given key.
  public mutating func add(key: String, binaryValue: Data) {
    self.add(key: key, value: .binary(binaryValue))
  }

  /// Add a new key-value pair.
  /// - Parameters:
  ///   - key: The key to be associated with the given value. If value is binary, it must end in `-bin`.
  ///   - value: The ``MetadataValue`` to be associated with the given key.
  public mutating func add(key: String, value: MetadataValue) {
    self.elements.append(.init(key: key, value: value))
  }

  /// Adds a key-value pair to the collection, where the value is a string.
  /// If there are pairs already associated to the given key, they will all be removed first, and the new pair
  /// will be added. If no pairs are present with the given key, a new one will be added.
  /// - Parameters:
  ///   - key: The key to be associated with the given value.
  ///   - stringValue: The string value to be associated with the given key.
  public mutating func replaceOrAdd(key: String, stringValue: String) {
    self.lockedElements.withLockedValue { elements in
      elements.removeAll { metadataKeyValue in
        metadataKeyValue.key == key
      }
      elements.append(.init(key: key, value: .string(stringValue)))
    }
  }

  /// Adds a key-value pair to the collection, where the value is `Data`.
  /// If there are pairs already associated to the given key, they will all be removed first, and the new pair
  /// will be added. If no pairs are present with the given key, a new one will be added.
  /// - Parameters:
  ///   - key: The key to be associated with the given value. Must end in `-bin`.
  ///   - binaryValue: The `Data` to be associated with the given key.
  public mutating func replaceOrAdd(key: String, binaryValue: Data) {
    self.lockedElements.withLockedValue { elements in
      elements.removeAll { metadataKeyValue in
        metadataKeyValue.key == key
      }
      elements.append(.init(key: key, value: .binary(binaryValue)))
    }
  }

  /// Adds a key-value pair to the collection.
  /// If there are pairs already associated to the given key, they will all be removed first, and the new pair
  /// will be added. If no pairs are present with the given key, a new one will be added.
  /// - Parameters:
  ///   - key: The key to be associated with the given value. If value is binary, it must end in `-bin`.
  ///   - value: The ``MetadataValue`` to be associated with the given key.
  public mutating func replaceOrAdd(key: String, value: MetadataValue) {
    self.lockedElements.withLockedValue { elements in
      elements.removeAll { metadataKeyValue in
        metadataKeyValue.key == key
      }
      elements.append(.init(key: key, value: value))
    }
  }
}

extension Metadata: RandomAccessCollection {
  public typealias Element = MetadataKeyValue

  public struct Index: Comparable, Sendable {
    @usableFromInline
    let _base: Array<Element>.Index

    @inlinable
    init(_base: Array<Element>.Index) {
      self._base = _base
    }

    @inlinable
    public static func < (lhs: Index, rhs: Index) -> Bool {
      return lhs._base < rhs._base
    }
  }

  public var startIndex: Index {
    return .init(_base: self.elements.startIndex)
  }

  public var endIndex: Index {
    return .init(_base: self.elements.endIndex)
  }

  public func index(before i: Index) -> Index {
    return .init(_base: self.elements.index(before: i._base))
  }

  public func index(after i: Index) -> Index {
    return .init(_base: self.elements.index(after: i._base))
  }

  public subscript(position: Index) -> Element {
    self.elements[position._base]
  }
}

extension Metadata {

  /// An iterator for all string values associated with a given key.
  /// This iterator will only return values originally stored as strings for a given key.
  public struct StringValuesIterator: IteratorProtocol {
    private var metadataIterator: Metadata.Iterator
    private let key: String

    init(forKey key: String, metadata: Metadata) {
      self.metadataIterator = metadata.makeIterator()
      self.key = key
    }

    public mutating func next() -> String? {
      while let nextKeyValue = self.metadataIterator.next() {
        if nextKeyValue.key == self.key {
          switch nextKeyValue.value {
          case .string(let stringValue):
            return stringValue
          case .binary:
            continue
          }
        }
      }
      return nil
    }
  }

  /// Create a new ``StringValuesIterator`` that iterates over the string values for the given key.
  /// - Parameter key: The key over whose string values this iterator will iterate.
  /// - Returns: An iterator to iterate over string values for the given key.
  public func makeStringValuesIterator(forKey key: String) -> StringValuesIterator {
    StringValuesIterator(forKey: key, metadata: self)
  }

  /// A subscript to get a ``StringValuesIterator`` for a given key.
  public subscript(keyForStringValues key: String) -> StringValuesIterator {
    StringValuesIterator(forKey: key, metadata: self)
  }
}

extension Metadata {

  /// An iterator for all binary data values associated with a given key.
  /// This iterator will only return values originally stored as binary data for a given key.
  public struct BinaryValuesIterator: IteratorProtocol {
    private var metadataIterator: Metadata.Iterator
    private let key: String

    init(forKey key: String, metadata: Metadata) {
      self.metadataIterator = metadata.makeIterator()
      self.key = key
    }

    public mutating func next() -> Data? {
      while let nextKeyValue = self.metadataIterator.next() {
        if nextKeyValue.key == self.key {
          switch nextKeyValue.value {
          case .string:
            continue
          case .binary(let binaryValue):
            return binaryValue
          }
        }
      }
      return nil
    }
  }

  /// Create a new ``BinaryValuesIterator`` that iterates over the `Data` values for the given key.
  /// - Parameter key: The key over whose `Data` values this iterator will iterate.
  /// - Returns: An iterator to iterate over `Data` values for the given key.
  public func makeBinaryValuesIterator(forKey key: String) -> BinaryValuesIterator {
    BinaryValuesIterator(forKey: key, metadata: self)
  }

  /// A subscript to get a ``BinaryValuesIterator`` for a given key.
  public subscript(keyForBinaryValues key: String) -> BinaryValuesIterator {
    BinaryValuesIterator(forKey: key, metadata: self)
  }
}

extension Metadata: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, MetadataValue)...) {
    let elements = elements.map { MetadataKeyValue(key: $0, value: $1) }
    self.lockedElements = .init(elements)
  }
}
