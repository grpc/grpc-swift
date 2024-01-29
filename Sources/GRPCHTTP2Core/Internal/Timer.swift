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

import NIOCore

struct Timer {
  /// The delay to wait before running the task.
  private let delay: TimeAmount
  /// The task to run, if scheduled.
  private var task: Kind?
  /// Whether the task to schedule is repeated.
  private let `repeat`: Bool

  private enum Kind {
    case once(Scheduled<Void>)
    case repeated(RepeatedTask)

    func cancel() {
      switch self {
      case .once(let task):
        task.cancel()
      case .repeated(let task):
        task.cancel()
      }
    }
  }

  init(delay: TimeAmount, repeat: Bool = false) {
    self.delay = delay
    self.task = nil
    self.repeat = `repeat`
  }

  /// Schedule a task on the given `EventLoop`.
  mutating func schedule(on eventLoop: EventLoop, work: @escaping () throws -> Void) {
    self.task?.cancel()

    if self.repeat {
      let task = eventLoop.scheduleRepeatedTask(initialDelay: self.delay, delay: self.delay) { _ in
        try work()
      }
      self.task = .repeated(task)
    } else {
      let task = eventLoop.scheduleTask(in: self.delay, work)
      self.task = .once(task)
    }
  }

  /// Cancels the task, if one was scheduled.
  mutating func cancel() {
    self.task?.cancel()
    self.task = nil
  }
}
