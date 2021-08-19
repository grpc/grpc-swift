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
#if compiler(>=5.5)
@testable import GRPC
import NIOConcurrencyHelpers
import XCTest

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
internal class AsyncWriterTests: GRPCTestCase {
  func testSingleWriterHappyPath() {
    XCTAsyncTest {
      let delegate = CollectingDelegate<String, Int>()
      let writer = AsyncWriter(delegate: delegate)

      try await writer.write("jimmy")
      XCTAssertEqual(delegate.elements, ["jimmy"])

      try await writer.write("jab")
      XCTAssertEqual(delegate.elements, ["jimmy", "jab"])

      try await writer.finish(99)
      XCTAssertEqual(delegate.end, 99)
    }
  }

  func testPauseAndResumeWrites() {
    XCTAsyncTest {
      let delegate = CollectingDelegate<String, Int>()
      let writer = AsyncWriter(delegate: delegate)

      // pause
      await writer.testingOnly_toggleWritability()

      async let written1: Void = writer.write("wunch")
      XCTAssert(delegate.elements.isEmpty)

      // resume
      await writer.testingOnly_toggleWritability()
      try await written1
      XCTAssertEqual(delegate.elements, ["wunch"])

      try await writer.finish(0)
      XCTAssertEqual(delegate.end, 0)
    }
  }

  func testTooManyWrites() throws {
    XCTAsyncTest {
      let delegate = CollectingDelegate<String, Int>()
      // Zero pending elements means that any write when paused will trigger an error.
      let writer = AsyncWriter(maxPendingElements: 0, delegate: delegate)

      // pause
      await writer.testingOnly_toggleWritability()

      await XCTAssertThrowsError(try await writer.write("pontiac")) { error in
        XCTAssertEqual(error as? AsyncWriterError, .tooManyPendingWrites)
      }

      // resume (we must finish the writer.)
      await writer.testingOnly_toggleWritability()
      try await writer.finish(0)
      XCTAssertEqual(delegate.end, 0)
      XCTAssertTrue(delegate.elements.isEmpty)
    }
  }

  func testWriteAfterFinish() throws {
    XCTAsyncTest {
      let delegate = CollectingDelegate<String, Int>()
      let writer = AsyncWriter(delegate: delegate)

      try await writer.finish(0)
      XCTAssertEqual(delegate.end, 0)

      await XCTAssertThrowsError(try await writer.write("cheddar")) { error in
        XCTAssertEqual(error as? AsyncWriterError, .alreadyFinished)
      }

      XCTAssertTrue(delegate.elements.isEmpty)
    }
  }

  func testTooManyCallsToFinish() throws {
    XCTAsyncTest {
      let delegate = CollectingDelegate<String, Int>()
      let writer = AsyncWriter(delegate: delegate)

      try await writer.finish(0)
      XCTAssertEqual(delegate.end, 0)

      await XCTAssertThrowsError(try await writer.finish(1)) { error in
        XCTAssertEqual(error as? AsyncWriterError, .alreadyFinished)
      }

      // Still 0.
      XCTAssertEqual(delegate.end, 0)
    }
  }

  func testCallToFinishWhilePending() throws {
    XCTAsyncTest {
      let delegate = CollectingDelegate<String, Int>()
      let writer = AsyncWriter(delegate: delegate)

      // Pause.
      await writer.testingOnly_toggleWritability()

      async let finished: Void = writer.finish(42)
      XCTAssertNil(delegate.end)

      // Resume.
      await writer.testingOnly_toggleWritability()
      try await finished

      XCTAssertEqual(delegate.end, 42)
    }
  }

  func testTooManyCallsToFinishWhilePending() throws {
    XCTAsyncTest {
      let delegate = CollectingDelegate<String, Int>()
      let writer = AsyncWriter(delegate: delegate)

      // Pause.
      await writer.testingOnly_toggleWritability()

      // We want to test that when a finish has suspended that another task calling finish results
      // in an `AsyncWriterError.alreadyFinished` error.
      //
      // It's hard to achieve this reliably in an obvious way because we can't guarantee the
      // ordering of `Task`s or when they will be suspended during `finish`. However, by pausing the
      // writer and calling finish in two separate tasks we guarantee that one will run first and
      // suspend (because the writer is paused) and the other will throw an error. When one throws
      // an error it can resume the writer allowing the other task to resume successfully.
      await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          do {
            try await writer.finish(1)
          } catch {
            XCTAssertEqual(error as? AsyncWriterError, .alreadyFinished)
            // Resume.
            await writer.testingOnly_toggleWritability()
          }
        }

        group.addTask {
          do {
            try await writer.finish(2)
          } catch {
            XCTAssertEqual(error as? AsyncWriterError, .alreadyFinished)
            // Resume.
            await writer.testingOnly_toggleWritability()
          }
        }
      }

      // We should definitely be finished by this point.
      await XCTAssertThrowsError(try await writer.finish(3)) { error in
        XCTAssertEqual(error as? AsyncWriterError, .alreadyFinished)
      }
    }
  }
}

fileprivate final class CollectingDelegate<Element, End>: AsyncWriterDelegate {
  private let lock = Lock()
  private var _elements: [Element] = []
  private var _end: End?

  internal var elements: [Element] {
    return self.lock.withLock { self._elements }
  }

  internal var end: End? {
    return self.lock.withLock { self._end }
  }

  internal func write(_ element: Element) {
    self.lock.withLockVoid {
      self._elements.append(element)
    }
  }

  internal func writeEnd(_ end: End) {
    self.lock.withLockVoid {
      self._end = end
    }
  }
}

#endif // compiler(>=5.5)
