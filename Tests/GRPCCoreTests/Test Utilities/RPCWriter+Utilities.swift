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

extension RPCWriter {
  /// Returns a writer which calls `XCTFail(_:)` on every write.
  static func failTestOnWrite(elementType: Element.Type = Element.self) -> Self {
    return RPCWriter(wrapping: FailOnWrite())
  }

  /// Returns a writer which gathers writes into an `AsyncStream`.
  static func gathering(into continuation: AsyncStream<Element>.Continuation) -> Self {
    return RPCWriter(wrapping: AsyncStreamGatheringWriter(continuation: continuation))
  }
}

private struct FailOnWrite<Element: Sendable>: RPCWriterProtocol {
  func write(_ element: Element) async throws {
    XCTFail("Unexpected write")
  }

  func write(contentsOf elements: some Sequence<Element>) async throws {
    XCTFail("Unexpected write")
  }
}

private struct AsyncStreamGatheringWriter<Element: Sendable>: RPCWriterProtocol {
  let continuation: AsyncStream<Element>.Continuation

  init(continuation: AsyncStream<Element>.Continuation) {
    self.continuation = continuation
  }

  func write(_ element: Element) {
    self.continuation.yield(element)
  }

  func write(contentsOf elements: some Sequence<Element>) {
    for element in elements {
      self.write(element)
    }
  }
}
