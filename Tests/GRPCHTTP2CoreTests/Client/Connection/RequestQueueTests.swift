/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

@testable import GRPCHTTP2Core

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class RequestQueueTests: XCTestCase {
  struct AnErrorToAvoidALeak: Error {}

  func testPopFirstEmpty() {
    var queue = RequestQueue()
    XCTAssertNil(queue.popFirst())
  }

  func testPopFirstNonEmpty() async {
    _ = try? await withCheckedThrowingContinuation { continuation in
      var queue = RequestQueue()
      let id = QueueEntryID()

      queue.append(continuation: continuation, waitForReady: false, id: id)
      guard let popped = queue.popFirst() else {
        return XCTFail("Missing continuation")
      }
      XCTAssertNil(queue.popFirst())

      popped.resume(throwing: AnErrorToAvoidALeak())
    }
  }

  func testPopFirstMultiple() async {
    await withTaskGroup(of: QueueEntryID.self) { group in
      let queue = _LockedValueBox(RequestQueue())
      let signal1 = AsyncStream.makeStream(of: Void.self)
      let signal2 = AsyncStream.makeStream(of: Void.self)

      let id1 = QueueEntryID()
      let id2 = QueueEntryID()

      group.addTask {
        _ = try? await withCheckedThrowingContinuation { continuation in
          queue.withLockedValue {
            $0.append(continuation: continuation, waitForReady: false, id: id1)
          }

          signal1.continuation.yield()
          signal1.continuation.finish()
        }

        return id1
      }

      group.addTask {
        // Wait until instructed to append.
        for await _ in signal1.stream {}

        _ = try? await withCheckedThrowingContinuation { continuation in
          queue.withLockedValue {
            $0.append(continuation: continuation, waitForReady: false, id: id2)
          }

          signal2.continuation.yield()
          signal2.continuation.finish()
        }

        return id2
      }

      // Wait for both continuations to be enqueued.
      for await _ in signal2.stream {}

      for id in [id1, id2] {
        let continuation = queue.withLockedValue { $0.popFirst() }
        continuation?.resume(throwing: AnErrorToAvoidALeak())
        let actual = await group.next()
        XCTAssertEqual(id, actual)
      }
    }
  }

  func testRemoveEntryByID() async {
    _ = try? await withCheckedThrowingContinuation { continuation in
      var queue = RequestQueue()
      let id = QueueEntryID()

      queue.append(continuation: continuation, waitForReady: false, id: id)
      guard let popped = queue.removeEntry(withID: id) else {
        return XCTFail("Missing continuation")
      }
      XCTAssertNil(queue.removeEntry(withID: id))

      popped.resume(throwing: AnErrorToAvoidALeak())
    }
  }

  func testRemoveEntryByIDMultiple() async {
    await withTaskGroup(of: QueueEntryID.self) { group in
      let queue = _LockedValueBox(RequestQueue())
      let signal1 = AsyncStream.makeStream(of: Void.self)
      let signal2 = AsyncStream.makeStream(of: Void.self)

      let id1 = QueueEntryID()
      let id2 = QueueEntryID()

      group.addTask {
        _ = try? await withCheckedThrowingContinuation { continuation in
          queue.withLockedValue {
            $0.append(continuation: continuation, waitForReady: false, id: id1)
          }

          signal1.continuation.yield()
          signal1.continuation.finish()
        }

        return id1
      }

      group.addTask {
        // Wait until instructed to append.
        for await _ in signal1.stream {}

        _ = try? await withCheckedThrowingContinuation { continuation in
          queue.withLockedValue {
            $0.append(continuation: continuation, waitForReady: false, id: id2)
          }

          signal2.continuation.yield()
          signal2.continuation.finish()
        }

        return id2
      }

      // Wait for both continuations to be enqueued.
      for await _ in signal2.stream {}

      for id in [id1, id2] {
        let continuation = queue.withLockedValue { $0.removeEntry(withID: id) }
        continuation?.resume(throwing: AnErrorToAvoidALeak())
        let actual = await group.next()
        XCTAssertEqual(id, actual)
      }
    }
  }

  func testRemoveFastFailingEntries() async throws {
    let queue = _LockedValueBox(RequestQueue())
    let enqueued = AsyncStream.makeStream(of: Void.self)

    try await withThrowingTaskGroup(of: Void.self) { group in
      var waitForReadyIDs = [QueueEntryID]()
      var failFastIDs = [QueueEntryID]()

      for _ in 0 ..< 50 {
        waitForReadyIDs.append(QueueEntryID())
        failFastIDs.append(QueueEntryID())
      }

      for ids in [waitForReadyIDs, failFastIDs] {
        let waitForReady = ids == waitForReadyIDs
        for id in ids {
          group.addTask {
            do {
              _ = try await withCheckedThrowingContinuation { continuation in
                queue.withLockedValue {
                  $0.append(continuation: continuation, waitForReady: waitForReady, id: id)
                }
                enqueued.continuation.yield()
              }
            } catch is AnErrorToAvoidALeak {
              ()
            }
          }
        }
      }

      // Wait for all continuations to be enqueued.
      var numberEnqueued = 0
      for await _ in enqueued.stream {
        numberEnqueued += 1
        if numberEnqueued == (waitForReadyIDs.count + failFastIDs.count) {
          enqueued.continuation.finish()
        }
      }

      // Remove all fast-failing continuations.
      let continuations = queue.withLockedValue {
        $0.removeFastFailingEntries()
      }

      for continuation in continuations {
        continuation.resume(throwing: AnErrorToAvoidALeak())
      }

      for id in failFastIDs {
        queue.withLockedValue {
          XCTAssertNil($0.removeEntry(withID: id))
        }
      }

      for id in waitForReadyIDs {
        let maybeContinuation = queue.withLockedValue { $0.removeEntry(withID: id) }
        let continuation = try XCTUnwrap(maybeContinuation)
        continuation.resume(throwing: AnErrorToAvoidALeak())
      }
    }
  }

  func testRemoveAll() async throws {
    let queue = _LockedValueBox(RequestQueue())
    let enqueued = AsyncStream.makeStream(of: Void.self)

    await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0 ..< 10 {
        group.addTask {
          _ = try await withCheckedThrowingContinuation { continuation in
            queue.withLockedValue {
              $0.append(continuation: continuation, waitForReady: false, id: QueueEntryID())
            }

            enqueued.continuation.yield()
          }
        }
      }

      // Wait for all continuations to be enqueued.
      var numberEnqueued = 0
      for await _ in enqueued.stream {
        numberEnqueued += 1
        if numberEnqueued == 10 {
          enqueued.continuation.finish()
        }
      }

      let continuations = queue.withLockedValue { $0.removeAll() }
      XCTAssertEqual(continuations.count, 10)
      XCTAssertNil(queue.withLockedValue { $0.popFirst() })

      for continuation in continuations {
        continuation.resume(throwing: AnErrorToAvoidALeak())
      }
    }
  }
}
