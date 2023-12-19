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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
private struct FailOnWrite<Element>: RPCWriterProtocol {
  func write(contentsOf elements: some Sequence<Element>) async throws {
    XCTFail("Unexpected write")
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
private struct AsyncStreamGatheringWriter<Element>: RPCWriterProtocol {
  let continuation: AsyncStream<Element>.Continuation

  init(continuation: AsyncStream<Element>.Continuation) {
    self.continuation = continuation
  }

  func write(contentsOf elements: some Sequence<Element>) async throws {
    for element in elements {
      self.continuation.yield(element)
    }
  }
}
