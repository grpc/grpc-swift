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

private import Synchronization

/// Stores cancellation state for an RPC on the server .
@available(gRPCSwift 2.0, *)
package final class ServerCancellationManager: Sendable {
  private let state: Mutex<State>

  package init() {
    self.state = Mutex(State())
  }

  /// Returns whether the RPC has been marked as cancelled.
  package var isRPCCancelled: Bool {
    self.state.withLock {
      return $0.isRPCCancelled
    }
  }

  /// Marks the RPC as cancelled, potentially running any cancellation handlers.
  package func cancelRPC() {
    switch self.state.withLock({ $0.cancelRPC() }) {
    case .executeAndResume(let onCancelHandlers, let onCancelWaiters):
      for handler in onCancelHandlers {
        handler.handler()
      }

      for onCancelWaiter in onCancelWaiters {
        switch onCancelWaiter {
        case .taskCancelled:
          ()
        case .waiting(_, let continuation):
          continuation.resume(returning: .rpc)
        }
      }

    case .doNothing:
      ()
    }
  }

  /// Adds a handler which is invoked when the RPC is cancelled.
  ///
  /// - Returns: The ID of the handler, if it was added, or `nil` if the RPC is already cancelled.
  package func addRPCCancelledHandler(_ handler: @Sendable @escaping () -> Void) -> UInt64? {
    return self.state.withLock { state -> UInt64? in
      state.addRPCCancelledHandler(handler)
    }
  }

  /// Removes a handler by its ID.
  package func removeRPCCancelledHandler(withID id: UInt64) {
    self.state.withLock { state in
      state.removeRPCCancelledHandler(withID: id)
    }
  }

  /// Suspends until the RPC is cancelled or the `Task` is cancelled.
  package func suspendUntilRPCIsCancelled() async throws(CancellationError) {
    let id = self.state.withLock { $0.nextID() }

    let source = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let onAddWaiter = self.state.withLock {
          $0.addRPCIsCancelledWaiter(continuation: continuation, withID: id)
        }

        switch onAddWaiter {
        case .doNothing:
          ()
        case .complete(let continuation, let result):
          continuation.resume(returning: result)
        }
      }
    } onCancel: {
      switch self.state.withLock({ $0.cancelRPCCancellationWaiter(withID: id) }) {
      case .resume(let continuation, let result):
        continuation.resume(returning: result)
      case .doNothing:
        ()
      }
    }

    switch source {
    case .rpc:
      ()
    case .task:
      throw CancellationError()
    }
  }
}

@available(gRPCSwift 2.0, *)
extension ServerCancellationManager {
  enum CancellationSource {
    case rpc
    case task
  }

  struct Handler: Sendable {
    var id: UInt64
    var handler: @Sendable () -> Void
  }

  enum Waiter: Sendable {
    case waiting(UInt64, CheckedContinuation<CancellationSource, Never>)
    case taskCancelled(UInt64)

    var id: UInt64 {
      switch self {
      case .waiting(let id, _):
        return id
      case .taskCancelled(let id):
        return id
      }
    }
  }

  struct State {
    private var handlers: [Handler]
    private var waiters: [Waiter]
    private var _nextID: UInt64
    var isRPCCancelled: Bool

    mutating func nextID() -> UInt64 {
      let id = self._nextID
      self._nextID &+= 1
      return id
    }

    init() {
      self.handlers = []
      self.waiters = []
      self._nextID = 0
      self.isRPCCancelled = false
    }

    mutating func cancelRPC() -> OnCancelRPC {
      let onCancel: OnCancelRPC

      if self.isRPCCancelled {
        onCancel = .doNothing
      } else {
        self.isRPCCancelled = true
        onCancel = .executeAndResume(self.handlers, self.waiters)
        self.handlers = []
        self.waiters = []
      }

      return onCancel
    }

    mutating func addRPCCancelledHandler(_ handler: @Sendable @escaping () -> Void) -> UInt64? {
      if self.isRPCCancelled {
        handler()
        return nil
      } else {
        let id = self.nextID()
        self.handlers.append(.init(id: id, handler: handler))
        return id
      }
    }

    mutating func removeRPCCancelledHandler(withID id: UInt64) {
      if let index = self.handlers.firstIndex(where: { $0.id == id }) {
        self.handlers.remove(at: index)
      }
    }

    enum OnCancelRPC {
      case executeAndResume([Handler], [Waiter])
      case doNothing
    }

    enum OnAddWaiter {
      case complete(CheckedContinuation<CancellationSource, Never>, CancellationSource)
      case doNothing
    }

    mutating func addRPCIsCancelledWaiter(
      continuation: CheckedContinuation<CancellationSource, Never>,
      withID id: UInt64
    ) -> OnAddWaiter {
      let onAddWaiter: OnAddWaiter

      if self.isRPCCancelled {
        onAddWaiter = .complete(continuation, .rpc)
      } else if let index = self.waiters.firstIndex(where: { $0.id == id }) {
        switch self.waiters[index] {
        case .taskCancelled:
          onAddWaiter = .complete(continuation, .task)
        case .waiting:
          // There's already a continuation enqueued.
          fatalError("Inconsistent state")
        }
      } else {
        self.waiters.append(.waiting(id, continuation))
        onAddWaiter = .doNothing
      }

      return onAddWaiter
    }

    enum OnCancelRPCCancellationWaiter {
      case resume(CheckedContinuation<CancellationSource, Never>, CancellationSource)
      case doNothing
    }

    mutating func cancelRPCCancellationWaiter(withID id: UInt64) -> OnCancelRPCCancellationWaiter {
      let onCancelWaiter: OnCancelRPCCancellationWaiter

      if let index = self.waiters.firstIndex(where: { $0.id == id }) {
        let waiter = self.waiters.removeWithoutMaintainingOrder(at: index)
        switch waiter {
        case .taskCancelled:
          onCancelWaiter = .doNothing
        case .waiting(_, let continuation):
          onCancelWaiter = .resume(continuation, .task)
        }
      } else {
        self.waiters.append(.taskCancelled(id))
        onCancelWaiter = .doNothing
      }

      return onCancelWaiter
    }
  }
}

extension Array {
  fileprivate mutating func removeWithoutMaintainingOrder(at index: Int) -> Element {
    let lastElementIndex = self.index(before: self.endIndex)

    if index == lastElementIndex {
      return self.remove(at: index)
    } else {
      self.swapAt(index, lastElementIndex)
      return self.removeLast()
    }
  }
}
