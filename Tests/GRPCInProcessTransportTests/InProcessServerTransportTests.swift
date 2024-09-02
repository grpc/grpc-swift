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

import XCTest

@testable import GRPCCore
@testable import GRPCInProcessTransport

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class InProcessServerTransportTests: XCTestCase {
  func testStartListening() async throws {
    let transport = InProcessServerTransport()

    let outbound = AsyncThrowingStream.makeStream(of: RPCResponsePart.self)
    let stream = RPCStream<
      RPCAsyncSequence<RPCRequestPart, any Error>,
      RPCWriter<RPCResponsePart>.Closable
    >(
      descriptor: .init(service: "testService", method: "testMethod"),
      inbound: RPCAsyncSequence<RPCRequestPart, any Error>(
        wrapping: AsyncThrowingStream {
          $0.yield(.message([42]))
          $0.finish()
        }
      ),
      outbound: RPCWriter.Closable(wrapping: outbound.continuation)
    )

    let messages = LockedValueBox<[RPCRequestPart]?>(nil)
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await transport.listen { stream in
          let partValue = try? await stream.inbound.reduce(into: []) { $0.append($1) }
          messages.withLockedValue { $0 = partValue }
          transport.stopListening()
        }
      }

      try transport.acceptStream(stream)
    }

    XCTAssertEqual(messages.withLockedValue { $0 }, [.message([42])])
  }

  func testStopListening() async throws {
    let transport = InProcessServerTransport()

    let firstStreamOutbound = AsyncThrowingStream.makeStream(of: RPCResponsePart.self)
    let firstStream = RPCStream<
      RPCAsyncSequence<RPCRequestPart, any Error>, RPCWriter<RPCResponsePart>.Closable
    >(
      descriptor: .init(service: "testService1", method: "testMethod1"),
      inbound: RPCAsyncSequence(
        wrapping: AsyncThrowingStream {
          $0.yield(.message([42]))
          $0.finish()
        }
      ),
      outbound: RPCWriter.Closable(wrapping: firstStreamOutbound.continuation)
    )

    try transport.acceptStream(firstStream)

    try await transport.listen { stream in
      let firstStreamMessages = try? await stream.inbound.reduce(into: []) {
        $0.append($1)
      }
      XCTAssertEqual(firstStreamMessages, [.message([42])])

      transport.stopListening()

      let secondStreamOutbound = AsyncThrowingStream.makeStream(of: RPCResponsePart.self)
      let secondStream = RPCStream<
        RPCAsyncSequence<RPCRequestPart, any Error>, RPCWriter<RPCResponsePart>.Closable
      >(
        descriptor: .init(service: "testService1", method: "testMethod1"),
        inbound: RPCAsyncSequence(
          wrapping: AsyncThrowingStream {
            $0.yield(.message([42]))
            $0.finish()
          }
        ),
        outbound: RPCWriter.Closable(wrapping: secondStreamOutbound.continuation)
      )

      XCTAssertThrowsError(ofType: RPCError.self) {
        try transport.acceptStream(secondStream)
      } errorHandler: { error in
        XCTAssertEqual(error.code, .failedPrecondition)
        XCTAssertEqual(error.message, "The server transport is closed.")
      }
    }
  }
}
