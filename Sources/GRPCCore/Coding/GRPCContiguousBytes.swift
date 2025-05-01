/*
 * Copyright 2025, gRPC Authors All rights reserved.
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

/// A bag-of-bytes type.
///
/// This protocol is used by the transport protocols (``ClientTransport`` and ``ServerTransport``)
/// with the serialization protocols (``MessageSerializer`` and ``MessageDeserializer``) so that
/// messages don't have to be copied to a fixed intermediate bag-of-bytes types.
@available(gRPCSwift 2.0, *)
public protocol GRPCContiguousBytes {
  /// Initialize the bytes to a repeated value.
  ///
  /// - Parameters:
  ///   - byte: The value to be repeated.
  ///   - count: The number of times to repeat the byte value.
  init(repeating byte: UInt8, count: Int)

  /// Initialize the bag of bytes from a sequence of bytes.
  ///
  /// - Parameters:
  ///   - sequence: a sequence of `UInt8` from which the bag of bytes should be constructed.
  init<Bytes: Sequence>(_ sequence: Bytes) where Bytes.Element == UInt8

  /// The number of bytes in the bag of bytes.
  var count: Int { get }

  /// Calls the given closure with the contents of underlying storage.
  ///
  /// - Note: Calling `withUnsafeBytes` multiple times does not guarantee that
  ///         the same buffer pointer will be passed in every time.
  /// - Warning: The buffer argument to the body should not be stored or used
  ///            outside of the lifetime of the call to the closure.
  func withUnsafeBytes<R>(_ body: (_ buffer: UnsafeRawBufferPointer) throws -> R) rethrows -> R

  /// Calls the given closure with the contents of underlying storage.
  ///
  /// - Note: Calling `withUnsafeBytes` multiple times does not guarantee that
  ///         the same buffer pointer will be passed in every time.
  /// - Warning: The buffer argument to the body should not be stored or used
  ///            outside of the lifetime of the call to the closure.
  mutating func withUnsafeMutableBytes<R>(
    _ body: (_ buffer: UnsafeMutableRawBufferPointer) throws -> R
  ) rethrows -> R
}

@available(gRPCSwift 2.0, *)
extension [UInt8]: GRPCContiguousBytes {}
