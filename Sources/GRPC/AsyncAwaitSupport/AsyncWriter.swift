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
import NIOCore

/// An asynchronous writer which forwards messages to a delegate.
///
/// Forwarding of messages to the delegate may be paused and resumed by controlling the writability
/// of the writer. This may be controlled by calls to ``toggleWritability()``. When the writer is
/// paused (by becoming unwritable) calls to ``write(_:)`` may suspend. When the writer is resumed
/// (by becoming writable) any calls which are suspended may be resumed.
///
/// The writer must also be "finished" with a final value: as for writing, calls to ``finish(_:)``
/// may suspend if the writer has been paused.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
internal final actor AsyncWriter<Delegate: AsyncWriterDelegate> {
  @usableFromInline
  internal typealias Element = Delegate.Element

  @usableFromInline
  internal typealias End = Delegate.End

  /// A value pending a write.
  @usableFromInline
  internal struct _Pending<Value> {
    @usableFromInline
    var value: Value

    @usableFromInline
    var continuation: CheckedContinuation<Void, Error>

    @inlinable
    internal init(_ value: Value, continuation: CheckedContinuation<Void, Error>) {
      self.value = value
      self.continuation = continuation
    }
  }

  @usableFromInline
  typealias PendingElement = _Pending<Element>

  @usableFromInline
  typealias PendingEnd = _Pending<End>

  @usableFromInline
  internal enum _CompletionState {
    /// Finish hasn't been called yet. May move to `pending` or `completed`.
    case incomplete
    /// Finish has been called but the writer is paused. May move to `completed`.
    case pending(PendingEnd)
    /// The completion message has been sent to the delegate. This is a terminal state.
    case completed

    /// Move from `pending` to `completed` and return the `PendingCompletion`. Returns `nil` if
    /// the state was not `pending`.
    @inlinable
    mutating func completeIfPending() -> PendingEnd? {
      switch self {
      case let .pending(pending):
        self = .completed
        return pending
      case .incomplete, .completed:
        return nil
      }
    }

    @usableFromInline
    var isPendingOrCompleted: Bool {
      switch self {
      case .incomplete:
        return false
      case .pending, .completed:
        return true
      }
    }
  }

  /// The maximum number of pending elements. `pendingElements` must not grow beyond this limit.
  @usableFromInline
  internal let _maxPendingElements: Int

  /// The maximum number of writes to the delegate made in `resume` before yielding to allow other
  /// values to be queued.
  @usableFromInline
  internal let _maxWritesBeforeYield: Int

  /// Elements and continuations which have been buffered but are awaiting consumption by the
  /// delegate.
  @usableFromInline
  internal var _pendingElements: CircularBuffer<PendingElement>

  /// The completion state of the writer.
  @usableFromInline
  internal var _completionState: _CompletionState

  /// Whether the writer is paused.
  @usableFromInline
  internal var _isPaused: Bool = false

  /// The delegate to process elements. By convention we call the delegate before resuming any
  /// continuation.
  @usableFromInline
  internal let _delegate: Delegate

  @inlinable
  internal init(
    maxPendingElements: Int = 16,
    maxWritesBeforeYield: Int = 5,
    delegate: Delegate
  ) {
    self._maxPendingElements = maxPendingElements
    self._maxWritesBeforeYield = maxWritesBeforeYield
    self._pendingElements = CircularBuffer(initialCapacity: maxPendingElements)
    self._completionState = .incomplete
    self._delegate = delegate
  }

  deinit {
    switch self._completionState {
    case .completed:
      ()
    case .incomplete, .pending:
      assertionFailure("writer has not completed is pending completion")
    }
  }

  /// As ``toggleWritability()`` but executed asynchronously.
  @usableFromInline
  internal nonisolated func toggleWritabilityAsynchronously() {
    Task {
      await self.toggleWritability()
    }
  }

  /// Toggles whether the writer is writable or not. The writer is initially writable.
  ///
  /// If the writer becomes writable then it may resume writes to the delegate. If it becomes
  /// unwritable then calls to `write` may suspend until the writability changes again.
  ///
  /// This API does not offer explicit control over the writability state so the caller must ensure
  /// calls to this function correspond with changes in writability. The reason for this is that the
  /// underlying type is an `actor` and updating its state is therefore asynchronous. However,
  /// this functions is not called from an asynchronous context so it is not possible to `await`
  /// state updates to complete. Instead, changing the state is via a `nonisolated` function on
  /// the `actor` which spawns a new task. If this or a similar API allowed the writability to be
  /// explicitly set then calls to that API are not guaranteed to be ordered which may lead to
  /// deadlock.
  @usableFromInline
  internal func toggleWritability() async {
    if self._isPaused {
      self._isPaused = false
      await self.resumeWriting()
    } else {
      self._isPaused = true
    }
  }

  private func resumeWriting() async {
    var writes = 0

    while !self._isPaused {
      if let pendingElement = self._pendingElements.popFirst() {
        self._delegate.write(pendingElement.value)
        pendingElement.continuation.resume()
      } else if let pendingCompletion = self._completionState.completeIfPending() {
        self._delegate.writeEnd(pendingCompletion.value)
        pendingCompletion.continuation.resume()
      } else {
        break
      }

      // `writes` will never exceed `maxWritesBeforeYield` so unchecked arithmetic is okay here.
      writes &+= 1
      if writes == self._maxWritesBeforeYield {
        writes = 0
        // We yield every so often to let the delegate (i.e. 'NIO.Channel') catch up since it may
        // decide it is no longer writable.
        await Task.yield()
      }
    }
  }

  /// As ``cancel()`` but executed asynchronously.
  @usableFromInline
  internal nonisolated func cancelAsynchronously() {
    Task {
      await self.cancel()
    }
  }

  /// Cancel all pending writes.
  ///
  /// Any pending writes will be dropped and their continuations will be resumed with
  /// a `CancellationError`. Any writes after cancellation has completed will also fail.
  @usableFromInline
  internal func cancel() {
    // If there's an end we should fail that last.
    let pendingEnd: PendingEnd?

    // Mark our state as completed before resuming any continuations (any future writes should fail
    // immediately).
    switch self._completionState {
    case .incomplete:
      pendingEnd = nil
      self._completionState = .completed

    case let .pending(pending):
      pendingEnd = pending
      self._completionState = .completed

    case .completed:
      pendingEnd = nil
    }

    let cancellationError = CancellationError()

    while let pending = self._pendingElements.popFirst() {
      pending.continuation.resume(throwing: cancellationError)
    }

    pendingEnd?.continuation.resume(throwing: cancellationError)
  }

  /// Write an `element`.
  ///
  /// The call may be suspend if the writer is paused.
  ///
  /// Throws: ``GRPCAsyncWriterError`` if the writer has already been finished or too many write tasks
  ///   have been suspended.
  @inlinable
  internal func write(_ element: Element) async throws {
    try await withCheckedThrowingContinuation { continuation in
      self._write(element, continuation: continuation)
    }
  }

  @inlinable
  internal func _write(_ element: Element, continuation: CheckedContinuation<Void, Error>) {
    // There are three outcomes of writing:
    // - write the element directly (if the writer isn't paused and no writes are pending)
    // - queue the element (the writer is paused or there are writes already pending)
    // - error (the writer is complete or the queue is full).

    if self._completionState.isPendingOrCompleted {
      continuation.resume(throwing: GRPCAsyncWriterError.alreadyFinished)
    } else if !self._isPaused, self._pendingElements.isEmpty {
      self._delegate.write(element)
      continuation.resume()
    } else if self._pendingElements.count < self._maxPendingElements {
      // The continuation will be resumed later.
      self._pendingElements.append(PendingElement(element, continuation: continuation))
    } else {
      continuation.resume(throwing: GRPCAsyncWriterError.tooManyPendingWrites)
    }
  }

  /// Write the final element
  @inlinable
  internal func finish(_ end: End) async throws {
    try await withCheckedThrowingContinuation { continuation in
      self._finish(end, continuation: continuation)
    }
  }

  @inlinable
  internal func _finish(_ end: End, continuation: CheckedContinuation<Void, Error>) {
    if self._completionState.isPendingOrCompleted {
      continuation.resume(throwing: GRPCAsyncWriterError.alreadyFinished)
    } else if !self._isPaused, self._pendingElements.isEmpty {
      self._completionState = .completed
      self._delegate.writeEnd(end)
      continuation.resume()
    } else {
      // Either we're paused or there are pending writes which must be consumed first.
      self._completionState = .pending(PendingEnd(end, continuation: continuation))
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension AsyncWriter where End == Void {
  @inlinable
  internal func finish() async throws {
    try await self.finish(())
  }
}

public struct GRPCAsyncWriterError: Error, Hashable {
  private let wrapped: Wrapped

  @usableFromInline
  internal enum Wrapped {
    case tooManyPendingWrites
    case alreadyFinished
  }

  @usableFromInline
  internal init(_ wrapped: Wrapped) {
    self.wrapped = wrapped
  }

  /// There are too many writes pending. This may occur when too many Tasks are writing
  /// concurrently.
  public static let tooManyPendingWrites = Self(.tooManyPendingWrites)

  /// The writer has already finished. This may occur when the RPC completes prematurely, or when
  /// a user calls finish more than once.
  public static let alreadyFinished = Self(.alreadyFinished)
}

@usableFromInline
internal protocol AsyncWriterDelegate: AnyObject {
  associatedtype Element
  associatedtype End

  @inlinable
  func write(_ element: Element)

  @inlinable
  func writeEnd(_ end: End)
}

#endif // compiler(>=5.6)
