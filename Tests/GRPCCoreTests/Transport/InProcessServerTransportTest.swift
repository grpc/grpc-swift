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

final class InProcessServerTransportTest: XCTestCase {
  func testStartListening() async throws {
    let transport = InProcessServerTransport()
    let stream = RPCStream<RPCAsyncSequence<RPCRequestPart>, RPCWriter<RPCResponsePart>.Closable>(
      descriptor: .init(service: "testService", method: "testMethod"),
      inbound: .elements([.message([42])]),
      outbound: .init(
        wrapping: BufferedStream.Source(
          storage: .init(backPressureStrategy: .watermark(.init(low: 1, high: 1)))
        )
      )
    )

    let streamSequence = transport.listen()
    var streamSequenceInterator = streamSequence.makeAsyncIterator()

    try transport.acceptStream(stream)

    let testStream = try await streamSequenceInterator.next()
    let messages = try await testStream?.inbound.collect()
    XCTAssertEqual(messages, [.message([42])])
  }

  func testStopListening() async throws {
    let transport = InProcessServerTransport()
    let firstStream = RPCStream<
      RPCAsyncSequence<RPCRequestPart>, RPCWriter<RPCResponsePart>.Closable
    >(
      descriptor: .init(service: "testService1", method: "testMethod1"),
      inbound: .elements([.message([42])]),
      outbound: .init(
        wrapping: BufferedStream.Source(
          storage: .init(backPressureStrategy: .watermark(.init(low: 1, high: 1)))
        )
      )
    )

    let streamSequence = transport.listen()
    var streamSequenceInterator = streamSequence.makeAsyncIterator()

    try transport.acceptStream(firstStream)

    let firstTestStream = try await streamSequenceInterator.next()
    let firstStreamMessages = try await firstTestStream?.inbound.collect()
    XCTAssertEqual(firstStreamMessages, [.message([42])])

    transport.stopListening()

    let secondStream = RPCStream<
      RPCAsyncSequence<RPCRequestPart>, RPCWriter<RPCResponsePart>.Closable
    >(
      descriptor: .init(service: "testService1", method: "testMethod1"),
      inbound: .elements([.message([42])]),
      outbound: .init(
        wrapping: BufferedStream.Source(
          storage: .init(backPressureStrategy: .watermark(.init(low: 1, high: 1)))
        )
      )
    )

    XCTAssertThrowsRPCError(try transport.acceptStream(secondStream)) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
    }

    let secondTestStream = try await streamSequenceInterator.next()
    XCTAssertNil(secondTestStream)
  }
}
