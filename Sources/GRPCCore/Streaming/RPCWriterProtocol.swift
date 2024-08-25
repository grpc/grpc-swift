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

/// A sink for values which are produced over time.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol RPCWriterProtocol<Element>: Sendable {
  /// The type of value written.
  associatedtype Element

  /// Writes a single element.
  ///
  /// This function suspends until the element has been accepted. Implementers can use this
  /// to exert backpressure on callers.
  ///
  /// - Parameter element: The element to write.
  func write(_ element: Element) async throws

  /// Writes a sequence of elements.
  ///
  /// This function suspends until the elements have been accepted. Implementers can use this
  /// to exert backpressure on callers.
  ///
  /// - Parameter elements: The elements to write.
  func write(contentsOf elements: some Sequence<Element>) async throws
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension RPCWriterProtocol {
  /// Writes an `AsyncSequence` of values into the sink.
  ///
  /// - Parameter elements: The elements to write.
  public func write<Elements: AsyncSequence>(
    contentsOf elements: Elements
  ) async throws where Elements.Element == Element {
    for try await element in elements {
      try await self.write(element)
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol ClosableRPCWriterProtocol<Element>: RPCWriterProtocol {
  /// Indicate to the writer that no more writes are to be accepted.
  ///
  /// All writes after ``finish()`` has been called should result in an error
  /// being thrown.
  func finish()

  /// Indicate to the writer that no more writes are to be accepted because an error occurred.
  ///
  /// All writes after ``finish(throwing:)`` has been called should result in an error
  /// being thrown.
  func finish(throwing error: any Error)
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension AsyncThrowingStream.Continuation: RPCWriterProtocol {
  public func write(_ element: Element) async throws {
    self.yield(element)
  }

  public func write(contentsOf elements: some Sequence<Element>) async throws {
    for element in elements {
      self.yield(element)
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension AsyncThrowingStream.Continuation: ClosableRPCWriterProtocol where Failure == any Error {
  public func finish() {
    self.finish(throwing: nil)
  }

  public func finish(throwing error: any Error) {
    self.finish(throwing: .some(error))
  }
}
