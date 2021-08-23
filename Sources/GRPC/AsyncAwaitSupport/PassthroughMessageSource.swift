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
import NIOConcurrencyHelpers
import NIOCore

/// The source of messages for a ``PassthroughMessageSequence``.`
///
/// Values may be provided to the source with calls to ``yield(_:)`` which returns whether the value
/// was accepted (and how many values are yet to be consumed) -- or dropped.
///
/// The backing storage has an unbounded capacity and callers should use the number of unconsumed
/// values returned from ``yield(_:)`` as an indication of when to stop providing values.
///
/// The source must be finished exactly once by calling ``finish()`` or ``finish(throwing:)`` to
/// indicate that the sequence should end with an error.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
internal final class PassthroughMessageSource<Element, Failure: Error> {
  private typealias ContinuationResult = Result<Element?, Error>

  /// All state in this class must be accessed via the lock.
  ///
  /// - Important: We use a `class` with a lock rather than an `actor` as we must guarantee that
  ///   calls to ``yield(_:)`` are not reordered.
  private let lock: Lock

  /// A queue of elements which may be consumed as soon as there is demand.
  private var continuationResults: CircularBuffer<ContinuationResult>

  /// A continuation which will be resumed in the future. The continuation must be `nil`
  /// if ``continuationResults`` is not empty.
  private var continuation: Optional<CheckedContinuation<Element?, Error>>

  /// True if a terminal continuation result (`.success(nil)` or `.failure()`) has been seen.
  /// No more values may be enqueued to `continuationResults` if this is `true`.
  private var isTerminated: Bool

  internal init(initialBufferCapacity: Int = 16) {
    self.lock = Lock()
    self.continuationResults = CircularBuffer(initialCapacity: initialBufferCapacity)
    self.continuation = nil
    self.isTerminated = false
  }

  // MARK: - Append / Yield

  internal enum YieldResult: Hashable {
    /// The value was accepted. The `queueDepth` indicates how many elements are waiting to be
    /// consumed.
    ///
    /// If `queueDepth` is zero then the value was consumed immediately.
    case accepted(queueDepth: Int)

    /// The value was dropped because the source has already been finished.
    case dropped
  }

  internal func yield(_ element: Element) -> YieldResult {
    let continuationResult: ContinuationResult = .success(element)
    return self.yield(continuationResult, isTerminator: false)
  }

  internal func finish(throwing error: Failure? = nil) -> YieldResult {
    let continuationResult: ContinuationResult = error.map { .failure($0) } ?? .success(nil)
    return self.yield(continuationResult, isTerminator: true)
  }

  private enum _YieldResult {
    /// The sequence has already been terminated; drop the element.
    case alreadyTerminated
    /// The element was added to the queue to be consumed later.
    case queued(Int)
    /// Demand for an element already existed: complete the continuation with the result being
    /// yielded.
    case resume(CheckedContinuation<Element?, Error>)
  }

  private func yield(_ continuationResult: ContinuationResult, isTerminator: Bool) -> YieldResult {
    let yieldResult: YieldResult

    switch self._yield(continuationResult, isTerminator: isTerminator) {
    case let .queued(size):
      yieldResult = .accepted(queueDepth: size)
    case let .resume(continuation):
      // If we resume a continuation then the queue must be empty
      yieldResult = .accepted(queueDepth: 0)
      continuation.resume(with: continuationResult)
    case .alreadyTerminated:
      yieldResult = .dropped
    }

    return yieldResult
  }

  private func _yield(
    _ continuationResult: ContinuationResult,
    isTerminator: Bool
  ) -> _YieldResult {
    return self.lock.withLock {
      if self.isTerminated {
        return .alreadyTerminated
      } else if let continuation = self.continuation {
        self.continuation = nil
        return .resume(continuation)
      } else {
        self.isTerminated = isTerminator
        self.continuationResults.append(continuationResult)
        return .queued(self.continuationResults.count)
      }
    }
  }

  // MARK: - Next

  internal func consumeNextElement() async throws -> Element? {
    return try await withCheckedThrowingContinuation {
      self.consumeNextElement(continuation: $0)
    }
  }

  private func consumeNextElement(continuation: CheckedContinuation<Element?, Error>) {
    let continuationResult: ContinuationResult? = self.lock.withLock {
      if let nextResult = self.continuationResults.popFirst() {
        return nextResult
      } else {
        // Nothing buffered and not terminated yet: save the continuation for later.
        assert(self.continuation == nil)
        self.continuation = continuation
        return nil
      }
    }

    if let continuationResult = continuationResult {
      continuation.resume(with: continuationResult)
    }
  }
}

#endif // compiler(>=5.5)
