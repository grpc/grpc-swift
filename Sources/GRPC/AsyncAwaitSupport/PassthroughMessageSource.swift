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
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
internal final class PassthroughMessageSource<Element, Failure: Error> {
  @usableFromInline
  internal typealias _ContinuationResult = Result<Element?, Error>

  /// All state in this class must be accessed via the lock.
  ///
  /// - Important: We use a `class` with a lock rather than an `actor` as we must guarantee that
  ///   calls to ``yield(_:)`` are not reordered.
  @usableFromInline
  internal let _lock: Lock

  /// A queue of elements which may be consumed as soon as there is demand.
  @usableFromInline
  internal var _continuationResults: CircularBuffer<_ContinuationResult>

  /// A continuation which will be resumed in the future. The continuation must be `nil`
  /// if ``continuationResults`` is not empty.
  @usableFromInline
  internal var _continuation: Optional<CheckedContinuation<Element?, Error>>

  /// True if a terminal continuation result (`.success(nil)` or `.failure()`) has been seen.
  /// No more values may be enqueued to `continuationResults` if this is `true`.
  @usableFromInline
  internal var _isTerminated: Bool

  @usableFromInline
  internal init(initialBufferCapacity: Int = 16) {
    self._lock = Lock()
    self._continuationResults = CircularBuffer(initialCapacity: initialBufferCapacity)
    self._continuation = nil
    self._isTerminated = false
  }

  // MARK: - Append / Yield

  @usableFromInline
  internal enum YieldResult: Hashable {
    /// The value was accepted. The `queueDepth` indicates how many elements are waiting to be
    /// consumed.
    ///
    /// If `queueDepth` is zero then the value was consumed immediately.
    case accepted(queueDepth: Int)

    /// The value was dropped because the source has already been finished.
    case dropped
  }

  @inlinable
  @discardableResult
  internal func yield(_ element: Element) -> YieldResult {
    let continuationResult: _ContinuationResult = .success(element)
    return self._yield(continuationResult, isTerminator: false)
  }

  @inlinable
  @discardableResult
  internal func finish(throwing error: Failure? = nil) -> YieldResult {
    let continuationResult: _ContinuationResult = error.map { .failure($0) } ?? .success(nil)
    return self._yield(continuationResult, isTerminator: true)
  }

  @usableFromInline
  internal enum _YieldResult {
    /// The sequence has already been terminated; drop the element.
    case alreadyTerminated
    /// The element was added to the queue to be consumed later.
    case queued(Int)
    /// Demand for an element already existed: complete the continuation with the result being
    /// yielded.
    case resume(CheckedContinuation<Element?, Error>)
  }

  @inlinable
  internal func _yield(
    _ continuationResult: _ContinuationResult, isTerminator: Bool
  ) -> YieldResult {
    let result: _YieldResult = self._lock.withLock {
      if self._isTerminated {
        return .alreadyTerminated
      } else {
        self._isTerminated = isTerminator
      }

      if let continuation = self._continuation {
        self._continuation = nil
        return .resume(continuation)
      } else {
        self._continuationResults.append(continuationResult)
        return .queued(self._continuationResults.count)
      }
    }

    let yieldResult: YieldResult
    switch result {
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

  // MARK: - Next

  @inlinable
  internal func consumeNextElement() async throws -> Element? {
    self._lock.lock()
    if let nextResult = self._continuationResults.popFirst() {
      self._lock.unlock()
      return try nextResult.get()
    } else if self._isTerminated {
      self._lock.unlock()
      return nil
    }

    // Slow path; we need a continuation.
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        // Nothing buffered and not terminated yet: save the continuation for later.
        precondition(self._continuation == nil)
        self._continuation = continuation
        self._lock.unlock()
      }
    } onCancel: {
      let continuation: CheckedContinuation<Element?, Error>? = self._lock.withLock {
        let cont = self._continuation
        self._continuation = nil
        return cont
      }

      continuation?.resume(throwing: CancellationError())
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
// @unchecked is ok: mutable state is accessed/modified via a lock.
extension PassthroughMessageSource: @unchecked Sendable where Element: Sendable {}

#endif // compiler(>=5.6)
