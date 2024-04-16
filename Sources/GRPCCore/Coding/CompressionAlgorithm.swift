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

/// Message compression algorithms.
public struct CompressionAlgorithm: Hashable, Sendable {
  @_spi(Package)
  public enum Value: UInt8, Hashable, Sendable, CaseIterable {
    case none = 0
    case deflate
    case gzip
  }

  @_spi(Package)
  public let value: Value

  fileprivate init(_ algorithm: Value) {
    self.value = algorithm
  }

  /// No compression, sometimes referred to as 'identity' compression.
  public static var none: Self {
    Self(.none)
  }

  /// The 'deflate' compression algorithm.
  public static var deflate: Self {
    Self(.deflate)
  }

  /// The 'gzip' compression algorithm.
  public static var gzip: Self {
    Self(.gzip)
  }
}

/// A set of compression algorithms.
public struct CompressionAlgorithmSet: OptionSet, Hashable, Sendable {
  public var rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  private init(value: CompressionAlgorithm.Value) {
    self.rawValue = 1 << value.rawValue
  }

  /// No compression, sometimes referred to as 'identity' compression.
  public static var none: Self {
    return Self(value: .none)
  }

  /// The 'deflate' compression algorithm.
  public static var deflate: Self {
    return Self(value: .deflate)
  }

  /// The 'gzip' compression algorithm.
  public static var gzip: Self {
    return Self(value: .gzip)
  }

  /// All compression algorithms.
  public static var all: Self {
    return [.gzip, .deflate, .none]
  }

  /// Returns whether a given algorithm is present in the set.
  ///
  /// - Parameter algorithm: The algorithm to check.
  public func contains(_ algorithm: CompressionAlgorithm) -> Bool {
    return self.contains(CompressionAlgorithmSet(value: algorithm.value))
  }
}

extension CompressionAlgorithmSet {
  /// A sequence of ``CompressionAlgorithm`` values present in the set.
  public var elements: Elements {
    Elements(algorithmSet: self)
  }

  /// A sequence of ``CompressionAlgorithm`` values present in a ``CompressionAlgorithmSet``.
  public struct Elements: Sequence {
    public typealias Element = CompressionAlgorithm

    private let algorithmSet: CompressionAlgorithmSet

    init(algorithmSet: CompressionAlgorithmSet) {
      self.algorithmSet = algorithmSet
    }

    public func makeIterator() -> Iterator {
      return Iterator(algorithmSet: self.algorithmSet)
    }

    public struct Iterator: IteratorProtocol {
      private let algorithmSet: CompressionAlgorithmSet
      private var iterator: IndexingIterator<[CompressionAlgorithm.Value]>

      init(algorithmSet: CompressionAlgorithmSet) {
        self.algorithmSet = algorithmSet
        self.iterator = CompressionAlgorithm.Value.allCases.makeIterator()
      }

      public mutating func next() -> CompressionAlgorithm? {
        while let value = self.iterator.next() {
          if self.algorithmSet.contains(CompressionAlgorithmSet(value: value)) {
            return CompressionAlgorithm(value)
          }
        }

        return nil
      }
    }
  }
}
