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

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension TaskGroup {
  /// Adds a child task to the group which is individually cancellable.
  ///
  /// - Parameter operation: The task to add to the group.
  /// - Returns: A handle which can be used to cancel the task without cancelling the rest of
  ///     the group.
  @inlinable
  mutating func addCancellableTask(
    _ operation: @Sendable @escaping () async -> ChildTaskResult
  ) -> CancellableTaskHandle {
    let signal = AsyncStream.makeStream(of: Void.self)
    self.addTask {
      return await withTaskGroup(
        of: _ResultOrCancelled.self,
        returning: ChildTaskResult.self
      ) { group in
        group.addTask {
          let childTaskResult = await operation()
          return .result(childTaskResult)
        }

        group.addTask {
          for await _ in signal.stream {}
          return .cancelled
        }

        let first = await group.next()!
        group.cancelAll()
        let second = await group.next()!

        switch (first, second) {
        case (.result(let result), .cancelled), (.cancelled, .result(let result)):
          return result
        default:
          fatalError("Internal inconsistency")
        }
      }
    }

    return CancellableTaskHandle(continuation: signal.continuation)
  }

  @usableFromInline
  enum _ResultOrCancelled {
    case result(ChildTaskResult)
    case cancelled
  }
}

@usableFromInline
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
struct CancellableTaskHandle: Sendable {
  @usableFromInline
  private(set) var continuation: AsyncStream<Void>.Continuation

  @inlinable
  init(continuation: AsyncStream<Void>.Continuation) {
    self.continuation = continuation
  }

  @inlinable
  func cancel() {
    self.continuation.finish()
  }
}
