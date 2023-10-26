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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class BroadcastAsyncSequenceTests: XCTestCase {
  func testSingleSubscriberToEmptyStream() async throws {
    let (stream, source) = BroadcastAsyncSequence.makeStream(of: Int.self, bufferSize: 16)
    source.finish()
    let elements = try await stream.collect()
    XCTAssertEqual(elements, [])
  }

  func testMultipleSubscribersToEmptyStream() async throws {
    let (stream, source) = BroadcastAsyncSequence.makeStream(of: Int.self, bufferSize: 16)
    source.finish()
    do {
      let elements = try await stream.collect()
      XCTAssertEqual(elements, [])
    }
    do {
      let elements = try await stream.collect()
      XCTAssertEqual(elements, [])
    }
  }

  func testSubscribeToEmptyStreamBeforeFinish() async throws {
    let (stream, source) = BroadcastAsyncSequence.makeStream(of: Int.self, bufferSize: 16)
    var iterator = stream.makeAsyncIterator()
    source.finish()
    let element = try await iterator.next()
    XCTAssertNil(element)
  }

  func testSlowConsumerIsLeftBehind() async throws {
    let (stream, source) = BroadcastAsyncSequence.makeStream(of: Int.self, bufferSize: 16)
    var consumer1 = stream.makeAsyncIterator()
    var consumer2 = stream.makeAsyncIterator()

    for element in 0 ..< 15 {
      try await source.write(element)
    }

    // Buffer should now be full. Consume with one consumer so that the other is dropped on
    // the next yield.
    let element = try await consumer1.next()
    XCTAssertEqual(element, 0)

    // Will invalidate consumer2 as the slowest consumer.
    try await source.write(15)

    await XCTAssertThrowsErrorAsync {
      try await consumer2.next()
    } errorHandler: { error in
      XCTAssertEqual(error as? BroadcastAsyncSequenceError, .consumingTooSlow)
    }

    // consumer1 should be free to continue.
    for expected in 1 ... 15 {
      let element = try await consumer1.next()
      XCTAssertEqual(element, expected)
    }

    // consumer1 should end as expected.
    source.finish()
    let end = try await consumer1.next()
    XCTAssertNil(end)
  }

  func testConsumerJoiningAfterSomeElements() async throws {
    let (stream, source) = BroadcastAsyncSequence.makeStream(of: Int.self, bufferSize: 16)
    for element in 0 ..< 10 {
      try await source.write(element)
    }

    var consumer1 = stream.makeAsyncIterator()
    do {
      for expected in 0 ..< 8 {
        let element = try await consumer1.next()
        XCTAssertEqual(element, expected)
      }
    }

    // Add a second consumer, consume the first four elements.
    var consumer2 = stream.makeAsyncIterator()
    do {
      for expected in 0 ..< 4 {
        let element = try await consumer2.next()
        XCTAssertEqual(element, expected)
      }
    }

    // Add another consumer, consume the first two elements.
    var consumer3 = stream.makeAsyncIterator()
    do {
      for expected in 0 ..< 2 {
        let element = try await consumer3.next()
        XCTAssertEqual(element, expected)
      }
    }

    // Advance each consumer in lock-step.
    for offset in 0 ..< 10 {
      try await source.write(10 + offset)
      let element1 = try await consumer1.next()
      XCTAssertEqual(element1, 8 + offset)
      let element2 = try await consumer2.next()
      XCTAssertEqual(element2, 4 + offset)
      let element3 = try await consumer3.next()
      XCTAssertEqual(element3, 2 + offset)
    }

    // Subscribing isn't possible.
    await XCTAssertThrowsErrorAsync {
      try await stream.collect()
    } errorHandler: { error in
      XCTAssertEqual(error as? BroadcastAsyncSequenceError, .consumingTooSlow)
    }

    source.finish()

    // All elements are present. The existing consumers can finish however they choose.
    do {
      for expected in 18 ..< 20 {
        let element = try await consumer1.next()
        XCTAssertEqual(element, expected)
      }
      let end = try await consumer1.next()
      XCTAssertNil(end)
    }

    do {
      for expected in 14 ..< 20 {
        let element = try await consumer2.next()
        XCTAssertEqual(element, expected)
      }
      let end = try await consumer2.next()
      XCTAssertNil(end)
    }

    do {
      for expected in 12 ..< 20 {
        let element = try await consumer3.next()
        XCTAssertEqual(element, expected)
      }
      let end = try await consumer3.next()
      XCTAssertNil(end)
    }
  }

  func testInvalidateAllConsumersForSingleConcurrentConsumer() async throws {
    let (stream, source) = BroadcastAsyncSequence.makeStream(of: Int.self, bufferSize: 16)
    for element in 0 ..< 10 {
      try await source.write(element)
    }

    var consumer1 = stream.makeAsyncIterator()
    stream.invalidateAllSubscriptions()
    await XCTAssertThrowsErrorAsync {
      try await consumer1.next()
    } errorHandler: { error in
      XCTAssertEqual(error as? BroadcastAsyncSequenceError, .consumingTooSlow)
    }

    // Subscribe, consume one, then cancel.
    var consumer2 = stream.makeAsyncIterator()
    do {
      let value = try await consumer2.next()
      XCTAssertEqual(value, 0)
    }
    stream.invalidateAllSubscriptions()
    await XCTAssertThrowsErrorAsync {
      try await consumer2.next()
    } errorHandler: { error in
      XCTAssertEqual(error as? BroadcastAsyncSequenceError, .consumingTooSlow)
    }
  }

  func testInvalidateAllConsumersForMultipleConcurrentConsumer() async throws {
    let (stream, source) = BroadcastAsyncSequence.makeStream(of: Int.self, bufferSize: 16)
    for element in 0 ..< 10 {
      try await source.write(element)
    }

    let consumers: [BroadcastAsyncSequence<Int>.AsyncIterator] = (0 ..< 5).map { _ in
      stream.makeAsyncIterator()
    }

    for var consumer in consumers {
      let value = try await consumer.next()
      XCTAssertEqual(value, 0)
    }

    stream.invalidateAllSubscriptions()

    for var consumer in consumers {
      await XCTAssertThrowsErrorAsync {
        try await consumer.next()
      } errorHandler: { error in
        XCTAssertEqual(error as? BroadcastAsyncSequenceError, .consumingTooSlow)
      }
    }
  }

  func testCancelSubscriber() async throws {
    let (stream, _) = BroadcastAsyncSequence.makeStream(of: Int.self, bufferSize: 16)
    await withTaskGroup(of: Void.self) { group in
      group.cancelAll()
      group.addTask {
        do {
          _ = try await stream.collect()
          XCTFail()
        } catch {
          XCTAssert(error is CancellationError)
        }
      }
    }
  }

  func testCancelProducer() async throws {
    let (_, source) = BroadcastAsyncSequence.makeStream(of: Int.self, bufferSize: 16)
    for i in 0 ..< 15 {
      try await source.write(i)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.cancelAll()
      for _ in 0 ..< 10 {
        group.addTask {
          try await source.write(42)
        }
      }

      while let result = await group.nextResult() {
        XCTAssertThrowsError(try result.get()) { error in
          XCTAssert(error is CancellationError)
        }
      }
    }
  }
}
