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

import DequeModule

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct RequestQueue {
  typealias Continuation = CheckedContinuation<LoadBalancer, Error>

  private struct QueueEntry {
    var continuation: Continuation
    var waitForReady: Bool
  }

  /// IDs of entries in the order they should be processed.
  ///
  /// If an ID is popped from the queue but isn't present in `entriesByID` then it must've
  /// been removed directly by its ID, this is fine.
  private var ids: Deque<QueueEntryID>

  /// Entries keyed by their ID.
  private var entriesByID: [QueueEntryID: QueueEntry]

  init() {
    self.ids = []
    self.entriesByID = [:]
  }

  /// Remove the first continuation from the queue.
  mutating func popFirst() -> Continuation? {
    while let id = self.ids.popFirst() {
      if let waiter = self.entriesByID.removeValue(forKey: id) {
        return waiter.continuation
      }
    }

    assert(self.entriesByID.isEmpty)
    return nil
  }

  /// Append a continuation to the queue.
  ///
  /// - Parameters:
  ///   - continuation: The continuation to append.
  ///   - waitForReady: Whether the request associated with the continuation is willing to wait for
  ///       the channel to become ready.
  ///   - id: The unique ID of the queue entry.
  mutating func append(continuation: Continuation, waitForReady: Bool, id: QueueEntryID) {
    let entry = QueueEntry(continuation: continuation, waitForReady: waitForReady)
    let removed = self.entriesByID.updateValue(entry, forKey: id)
    assert(removed == nil, "id '\(id)' reused")
    self.ids.append(id)
  }

  /// Remove the waiter with the given ID, if it exists.
  mutating func removeEntry(withID id: QueueEntryID) -> Continuation? {
    let waiter = self.entriesByID.removeValue(forKey: id)
    return waiter?.continuation
  }

  /// Remove all waiters, returning their continuations.
  mutating func removeAll() -> [Continuation] {
    let continuations = Array(self.entriesByID.values.map { $0.continuation })
    self.ids.removeAll(keepingCapacity: true)
    self.entriesByID.removeAll(keepingCapacity: true)
    return continuations
  }

  /// Remove all entries which were appended to the queue with a value of `false`
  /// for `waitForReady`.
  mutating func removeFastFailingEntries() -> [Continuation] {
    var removed = [Continuation]()
    var remainingIDs = Deque<QueueEntryID>()
    var remainingEntriesByID = [QueueEntryID: QueueEntry]()

    while let id = self.ids.popFirst() {
      guard let waiter = self.entriesByID.removeValue(forKey: id) else { continue }

      if waiter.waitForReady {
        remainingEntriesByID[id] = waiter
        remainingIDs.append(id)
      } else {
        removed.append(waiter.continuation)
      }
    }

    assert(self.entriesByID.isEmpty)
    self.entriesByID = remainingEntriesByID
    self.ids = remainingIDs
    return removed
  }
}
