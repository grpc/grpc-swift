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

/// A collection of metadata key-value pairs, found in RPC streams.
///
/// Metadata is a side channel associated with an RPC, that allows you to send information between clients
/// and servers. Metadata is stored as a list of key-value pairs where keys aren't required to be unique;
/// a single key may have multiple values associated with it.
///
/// Keys are case-insensitive ASCII strings. Values may be ASCII strings or binary data. The keys
/// for binary data should end with "-bin": this will be asserted when adding a new binary value.
/// Keys must not be prefixed with "grpc-" as these are reserved for gRPC.
///
/// # Using Metadata
///
/// You can add values to ``Metadata`` using the ``addString(_:forKey:)`` and
/// ``addBinary(_:forKey:)`` methods:
///
/// ```swift
/// var metadata = Metadata()
/// metadata.addString("value", forKey: "key")
/// metadata.addBinary([118, 97, 108, 117, 101], forKey: "key-bin")
/// ```
///
/// As ``Metadata`` conforms to `RandomAccessCollection` you can iterate over its values.
/// Because metadata can store strings and binary values, its `Element` type is an `enum` representing
/// both possibilities:
///
/// ```swift
/// for (key, value) in metadata {
///   switch value {
///   case .string(let value):
///     print("'\(key)' has a string value: '\(value)'")
///   case .binary(let value):
///     print("'\(key)' has a binary value: '\(value)'")
///   }
/// }
/// ```
///
/// You can also iterate over the values for a specific key:
///
/// ```swift
/// for value in metadata["key"] {
///   switch value {
///   case .string(let value):
///     print("'key' has a string value: '\(value)'")
///   case .binary(let value):
///     print("'key' has a binary value: '\(value)'")
///   }
/// }
/// ```
///
/// You can get only string or binary values for a key using ``subscript(stringValues:)`` and
/// ``subscript(binaryValues:)``:
///
/// ```swift
/// for value in metadata[stringValues: "key"] {
///   print("'key' has a string value: '\(value)'")
/// }
///
/// for value in metadata[binaryValues: "key"] {
///   print("'key' has a binary value: '\(value)'")
/// }
/// ```
///
/// - Note: Binary values are encoded as base64 strings when they are sent over the wire, so keys with
/// the "-bin" suffix may have string values (rather than binary). These are deserialized automatically when
/// using ``subscript(binaryValues:)``.
public struct Metadata: Sendable, Hashable {

  /// A metadata value. It can either be a simple string, or binary data.
  public enum Value: Sendable, Hashable {
    case string(String)
    case binary([UInt8])

    /// The value as a String. If it was originally stored as a binary, the base64-encoded String version
    /// of the binary data will be returned instead.
    public func encoded() -> String {
      switch self {
      case .string(let string):
        return string
      case .binary(let bytes):
        return Base64.encode(bytes: bytes)
      }
    }
  }

  /// A metadata key-value pair.
  internal struct KeyValuePair: Sendable, Hashable {
    internal let key: String
    internal let value: Value

    /// Constructor for a metadata key-value pair.
    ///
    /// - Parameters:
    ///   - key: The key for the key-value pair.
    ///   - value: The value to be associated to the given key. If it's a binary value, then the associated
    ///   key must end in "-bin", otherwise, this method will produce an assertion failure.
    init(key: String, value: Value) {
      if case .binary = value {
        assert(key.hasSuffix("-bin"), "Keys for binary values must end in -bin")
      }
      self.key = key
      self.value = value
    }
  }

  private var elements: [KeyValuePair]

  /// The Metadata collection's capacity.
  public var capacity: Int {
    self.elements.capacity
  }

  /// Initialize an empty Metadata collection.
  public init() {
    self.elements = []
  }

  /// Reserve the specified minimum capacity in the collection.
  ///
  /// - Parameter minimumCapacity: The minimum capacity to reserve in the collection.
  public mutating func reserveCapacity(_ minimumCapacity: Int) {
    self.elements.reserveCapacity(minimumCapacity)
  }

  /// Add a new key-value pair, where the value is a string.
  ///
  /// - Parameters:
  ///   - stringValue: The string value to be associated with the given key.
  ///   - key: The key to be associated with the given value.
  public mutating func addString(_ stringValue: String, forKey key: String) {
    self.addValue(.string(stringValue), forKey: key)
  }

  /// Add a new key-value pair, where the value is binary data, in the form of `[UInt8]`.
  ///
  /// - Parameters:
  ///   - binaryValue: The binary data (i.e., `[UInt8]`) to be associated with the given key.
  ///   - key: The key to be associated with the given value. Must end in "-bin".
  public mutating func addBinary(_ binaryValue: [UInt8], forKey key: String) {
    self.addValue(.binary(binaryValue), forKey: key)
  }

  /// Add a new key-value pair.
  ///
  /// - Parameters:
  ///   - value: The ``Value`` to be associated with the given key.
  ///   - key: The key to be associated with the given value. If value is binary, it must end in "-bin".
  internal mutating func addValue(_ value: Value, forKey key: String) {
    self.elements.append(.init(key: key, value: value))
  }

  /// Removes all values associated with the given key.
  ///
  /// - Parameter key: The key for which all values should be removed.
  ///
  /// - Complexity: O(*n*), where *n* is the number of entries in the metadata instance.
  public mutating func removeAllValues(forKey key: String) {
    elements.removeAll { metadataKeyValue in
      metadataKeyValue.key.isEqualCaseInsensitiveASCIIBytes(to: key)
    }
  }

  /// Adds a key-value pair to the collection, where the value is a string.
  ///
  /// If there are pairs already associated to the given key, they will all be removed first, and the new pair
  /// will be added. If no pairs are present with the given key, a new one will be added.
  ///
  /// - Parameters:
  ///   - stringValue: The string value to be associated with the given key.
  ///   - key: The key to be associated with the given value.
  ///
  /// - Complexity: O(*n*), where *n* is the number of entries in the metadata instance.
  public mutating func replaceOrAddString(_ stringValue: String, forKey key: String) {
    self.replaceOrAddValue(.string(stringValue), forKey: key)
  }

  /// Adds a key-value pair to the collection, where the value is `[UInt8]`.
  ///
  /// If there are pairs already associated to the given key, they will all be removed first, and the new pair
  /// will be added. If no pairs are present with the given key, a new one will be added.
  ///
  /// - Parameters:
  ///   - binaryValue: The `[UInt8]` to be associated with the given key.
  ///   - key: The key to be associated with the given value. Must end in "-bin".
  ///
  /// - Complexity: O(*n*), where *n* is the number of entries in the metadata instance.
  public mutating func replaceOrAddBinary(_ binaryValue: [UInt8], forKey key: String) {
    self.replaceOrAddValue(.binary(binaryValue), forKey: key)
  }

  /// Adds a key-value pair to the collection.
  ///
  /// If there are pairs already associated to the given key, they will all be removed first, and the new pair
  /// will be added. If no pairs are present with the given key, a new one will be added.
  ///
  /// - Parameters:
  ///   - value: The ``Value`` to be associated with the given key.
  ///   - key: The key to be associated with the given value. If value is binary, it must end in "-bin".
  ///
  /// - Complexity: O(*n*), where *n* is the number of entries in the metadata instance.
  internal mutating func replaceOrAddValue(_ value: Value, forKey key: String) {
    self.removeAllValues(forKey: key)
    self.elements.append(.init(key: key, value: value))
  }

  /// Removes all key-value pairs from this metadata instance.
  ///
  /// - Parameter keepingCapacity: Whether the current capacity should be kept or reset.
  ///
  /// - Complexity: O(*n*), where *n* is the number of entries in the metadata instance.
  public mutating func removeAll(keepingCapacity: Bool) {
    self.elements.removeAll(keepingCapacity: keepingCapacity)
  }

  /// Removes all elements which match the given predicate.
  ///
  /// - Parameter predicate: Returns `true` if the element should be removed.
  ///
  /// - Complexity: O(*n*), where *n* is the number of entries in the metadata instance.
  public mutating func removeAll(
    where predicate: (_ key: String, _ value: Value) throws -> Bool
  ) rethrows {
    try self.elements.removeAll { pair in
      try predicate(pair.key, pair.value)
    }
  }
}

extension Metadata: RandomAccessCollection {
  public typealias Element = (key: String, value: Value)

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
    let keyValuePair = self.elements[position._base]
    return (key: keyValuePair.key, value: keyValuePair.value)
  }
}

extension Metadata {

  /// A sequence of metadata values for a given key.
  public struct Values: Sequence {

    /// An iterator for all metadata ``Value``s associated with a given key.
    public struct Iterator: IteratorProtocol {
      private var metadataIterator: Metadata.Iterator
      private let key: String

      init(forKey key: String, metadata: Metadata) {
        self.metadataIterator = metadata.makeIterator()
        self.key = key
      }

      public mutating func next() -> Value? {
        while let nextKeyValue = self.metadataIterator.next() {
          if nextKeyValue.key.isEqualCaseInsensitiveASCIIBytes(to: self.key) {
            return nextKeyValue.value
          }
        }
        return nil
      }
    }

    private let key: String
    private let metadata: Metadata

    internal init(key: String, metadata: Metadata) {
      self.key = key
      self.metadata = metadata
    }

    public func makeIterator() -> Iterator {
      Iterator(forKey: self.key, metadata: self.metadata)
    }
  }

  /// Get a ``Values`` sequence for a given key.
  ///
  /// - Parameter key: The returned sequence will only return values for this key.
  ///
  /// - Returns: A sequence containing all values for the given key.
  public subscript(_ key: String) -> Values {
    Values(key: key, metadata: self)
  }
}

extension Metadata {

  /// A sequence of metadata string values for a given key.
  public struct StringValues: Sequence {

    /// An iterator for all string values associated with a given key.
    ///
    /// This iterator will only return values originally stored as strings for a given key.
    public struct Iterator: IteratorProtocol {
      private var values: Values.Iterator

      init(values: Values) {
        self.values = values.makeIterator()
      }

      public mutating func next() -> String? {
        while let value = self.values.next() {
          switch value {
          case .string(let stringValue):
            return stringValue
          case .binary:
            continue
          }
        }
        return nil
      }
    }

    private let key: String
    private let metadata: Metadata

    internal init(key: String, metadata: Metadata) {
      self.key = key
      self.metadata = metadata
    }

    public func makeIterator() -> Iterator {
      Iterator(values: Values(key: self.key, metadata: self.metadata))
    }
  }

  /// Get a ``StringValues`` sequence for a given key.
  ///
  /// - Parameter key: The returned sequence will only return string values for this key.
  ///
  /// - Returns: A sequence containing string values for the given key.
  public subscript(stringValues key: String) -> StringValues {
    StringValues(key: key, metadata: self)
  }
}

extension Metadata {

  /// A sequence of metadata binary values for a given key.
  public struct BinaryValues: Sequence {

    /// An iterator for all binary data values associated with a given key.
    ///
    /// This iterator will return values originally stored as binary data for a given key, and will also try to
    /// decode values stored as strings as if they were base64-encoded strings.
    public struct Iterator: IteratorProtocol {
      private var values: Values.Iterator

      init(values: Values) {
        self.values = values.makeIterator()
      }

      public mutating func next() -> [UInt8]? {
        while let value = self.values.next() {
          switch value {
          case .string(let stringValue):
            do {
              return try Base64.decode(string: stringValue)
            } catch {
              continue
            }
          case .binary(let binaryValue):
            return binaryValue
          }
        }
        return nil
      }
    }

    private let key: String
    private let metadata: Metadata

    internal init(key: String, metadata: Metadata) {
      self.key = key
      self.metadata = metadata
    }

    public func makeIterator() -> Iterator {
      Iterator(values: Values(key: self.key, metadata: self.metadata))
    }
  }

  /// A subscript to get a ``BinaryValues`` sequence for a given key.
  ///
  /// As it's iterated, this sequence will return values originally stored as binary data for a given key, and will
  /// also try to decode values stored as strings as if they were base64-encoded strings; only strings that
  /// are successfully decoded will be returned.
  ///
  /// - Parameter key: The returned sequence will only return binary (i.e. `[UInt8]`) values for this key.
  ///
  /// - Returns: A sequence containing binary (i.e. `[UInt8]`) values for the given key.
  ///
  /// - SeeAlso: ``BinaryValues/Iterator``.
  public subscript(binaryValues key: String) -> BinaryValues {
    BinaryValues(key: key, metadata: self)
  }
}

extension Metadata: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, Value)...) {
    self.elements = elements.map { KeyValuePair(key: $0, value: $1) }
  }
}

extension Metadata: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: (String, Value)...) {
    self.elements = elements.map { KeyValuePair(key: $0, value: $1) }
  }
}

extension Metadata.Value: ExpressibleByStringLiteral {
  public init(stringLiteral value: StringLiteralType) {
    self = .string(value)
  }
}

extension Metadata.Value: ExpressibleByStringInterpolation {
  public init(stringInterpolation: DefaultStringInterpolation) {
    self = .string(String(stringInterpolation: stringInterpolation))
  }
}

extension Metadata.Value: ExpressibleByArrayLiteral {
  public typealias ArrayLiteralElement = UInt8

  public init(arrayLiteral elements: ArrayLiteralElement...) {
    self = .binary(elements)
  }
}

extension Metadata: CustomStringConvertible {
  public var description: String {
    String(describing: self.map({ ($0.key, $0.value) }))
  }
}

extension Metadata.Value: CustomStringConvertible {
  public var description: String {
    switch self {
    case .string(let stringValue):
      return String(describing: stringValue)
    case .binary(let binaryValue):
      return String(describing: binaryValue)
    }
  }
}
