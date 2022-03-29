/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
#if compiler(>=5.6)
@testable import GRPC
import XCTest

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
class PassthroughMessageSourceTests: GRPCTestCase {
  func testBasicUsage() async throws {
    let source = PassthroughMessageSource<String, Never>()
    let sequence = PassthroughMessageSequence(consuming: source)

    XCTAssertEqual(source.yield("foo"), .accepted(queueDepth: 1))
    XCTAssertEqual(source.yield("bar"), .accepted(queueDepth: 2))
    XCTAssertEqual(source.yield("baz"), .accepted(queueDepth: 3))

    let firstTwo = try await sequence.prefix(2).collect()
    XCTAssertEqual(firstTwo, ["foo", "bar"])

    XCTAssertEqual(source.yield("bar"), .accepted(queueDepth: 2))
    XCTAssertEqual(source.yield("foo"), .accepted(queueDepth: 3))

    XCTAssertEqual(source.finish(), .accepted(queueDepth: 4))

    let theRest = try await sequence.collect()
    XCTAssertEqual(theRest, ["baz", "bar", "foo"])
  }

  func testFinishWithError() async throws {
    let source = PassthroughMessageSource<String, TestError>()

    XCTAssertEqual(source.yield("one"), .accepted(queueDepth: 1))
    XCTAssertEqual(source.yield("two"), .accepted(queueDepth: 2))
    XCTAssertEqual(source.yield("three"), .accepted(queueDepth: 3))
    XCTAssertEqual(source.finish(throwing: TestError()), .accepted(queueDepth: 4))

    // We should still be able to get the elements before the error.
    let sequence = PassthroughMessageSequence(consuming: source)
    let elements = try await sequence.prefix(3).collect()
    XCTAssertEqual(elements, ["one", "two", "three"])

    do {
      for try await element in sequence {
        XCTFail("Unexpected value '\(element)'")
      }
      XCTFail("AsyncSequence did not throw")
    } catch {
      XCTAssert(error is TestError)
    }
  }

  func testYieldAfterFinish() async throws {
    let source = PassthroughMessageSource<String, Never>()
    XCTAssertEqual(source.finish(), .accepted(queueDepth: 1))
    XCTAssertEqual(source.yield("foo"), .dropped)

    let sequence = PassthroughMessageSequence(consuming: source)
    let elements = try await sequence.count()
    XCTAssertEqual(elements, 0)
  }

  func testMultipleFinishes() async throws {
    let source = PassthroughMessageSource<String, TestError>()
    XCTAssertEqual(source.finish(), .accepted(queueDepth: 1))
    XCTAssertEqual(source.finish(), .dropped)
    XCTAssertEqual(source.finish(throwing: TestError()), .dropped)

    let sequence = PassthroughMessageSequence(consuming: source)
    let elements = try await sequence.count()
    XCTAssertEqual(elements, 0)
  }

  func testConsumeBeforeYield() async throws {
    let source = PassthroughMessageSource<String, Never>()
    let sequence = PassthroughMessageSequence(consuming: source)

    await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask(priority: .high) {
        let iterator = sequence.makeAsyncIterator()
        if let next = try await iterator.next() {
          XCTAssertEqual(next, "one")
        } else {
          XCTFail("No value produced")
        }
      }

      group.addTask(priority: .low) {
        let result = source.yield("one")
        // We can't guarantee that this task will run after the other so we *may* have a queue
        // depth of one.
        XCTAssert(result == .accepted(queueDepth: 0) || result == .accepted(queueDepth: 1))
      }
    }
  }

  func testConsumeBeforeFinish() async throws {
    let source = PassthroughMessageSource<String, TestError>()
    let sequence = PassthroughMessageSequence(consuming: source)

    await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask(priority: .high) {
        let iterator = sequence.makeAsyncIterator()
        await XCTAssertThrowsError(_ = try await iterator.next()) { error in
          XCTAssert(error is TestError)
        }
      }

      group.addTask(priority: .low) {
        let result = source.finish(throwing: TestError())
        // We can't guarantee that this task will run after the other so we *may* have a queue
        // depth of one.
        XCTAssert(result == .accepted(queueDepth: 0) || result == .accepted(queueDepth: 1))
      }
    }
  }
}

fileprivate struct TestError: Error {}

#endif // compiler(>=5.6)
