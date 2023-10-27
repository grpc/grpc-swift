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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension RPCWriter {
  @usableFromInline
  struct Closable: ClosableRPCWriterProtocol {
    @usableFromInline
    let writer: any ClosableRPCWriterProtocol<Element>

    /// Creates an ``RPCWriter`` by wrapping the `other` writer.
    ///
    /// - Parameter other: The writer to wrap.
    @inlinable
    init(wrapping other: some ClosableRPCWriterProtocol<Element>) {
      self.writer = other
    }

    /// Writes a sequence of elements.
    ///
    /// This function suspends until the elements have been accepted. Implements can use this
    /// to exert backpressure on callers.
    ///
    /// - Parameter elements: The elements to write.
    @inlinable
    func write(contentsOf elements: some Sequence<Element>) async throws {
      try await self.writer.write(contentsOf: elements)
    }

    /// Indicate to the writer that no more writes are to be accepted.
    ///
    /// All writes after ``finish()`` has been called should result in an error
    /// being thrown.
    @inlinable
    func finish() {
      self.writer.finish()
    }

    /// Indicate to the writer that no more writes are to be accepted because an error occurred.
    ///
    /// All writes after ``finish(throwing:)`` has been called should result in an error
    /// being thrown.
    @inlinable
    func finish(throwing error: Error) {
      self.writer.finish(throwing: error)
    }
  }
}
