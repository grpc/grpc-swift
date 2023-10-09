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

/// A type-erasing ``RPCWriterProtocol``.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct RPCWriter<Element>: Sendable, RPCWriterProtocol {
  private let writer: any RPCWriterProtocol<Element>

  /// Creates an ``RPCWriter`` by wrapping the `other` writer.
  ///
  /// - Parameter other: The writer to wrap.
  public init(wrapping other: some RPCWriterProtocol<Element>) {
    self.writer = other
  }

  /// Writes a sequence of elements.
  ///
  /// This function suspends until the elements have been accepted. Implements can use this
  /// to exert backpressure on callers.
  ///
  /// - Parameter elements: The elements to write.
  public func write(contentsOf elements: some Sequence<Element>) async throws {
    try await self.writer.write(contentsOf: elements)
  }
}
