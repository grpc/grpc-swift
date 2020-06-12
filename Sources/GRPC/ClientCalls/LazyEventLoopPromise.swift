/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIO
import NIOConcurrencyHelpers

extension EventLoop {
  internal func makeLazyPromise<Value>(of: Value.Type = Value.self) -> LazyEventLoopPromise<Value> {
    return LazyEventLoopPromise(on: self)
  }
}

/// A `LazyEventLoopPromise` is similar to an `EventLoopPromise` except that the underlying
/// `EventLoopPromise` promise is only created if it is required. That is, when the future result
/// has been requested and the promise has not yet been completed.
///
/// Note that all methods **must** be called from its `eventLoop`.
internal struct LazyEventLoopPromise<Value> {
  private enum State {
    // No future has been requested, no result has been delivered.
    case idle

    // No future has been requested, but this result have been delivered.
    case resolvedResult(Result<Value, Error>)

    // A future has been request; the promise may or may not contain a result.
    case unresolvedPromise(EventLoopPromise<Value>)

    // A future was requested, it's also been resolved.
    case resolvedFuture(EventLoopFuture<Value>)
  }

  private var state: State
  private let eventLoop: EventLoop

  fileprivate init(on eventLoop: EventLoop) {
    self.state = .idle
    self.eventLoop = eventLoop
  }

  /// Get the future result of this promise.
  internal mutating func getFutureResult() -> EventLoopFuture<Value> {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case .idle:
      let promise = self.eventLoop.makePromise(of: Value.self)
      self.state = .unresolvedPromise(promise)
      return promise.futureResult

    case .resolvedResult(let result):
      let future: EventLoopFuture<Value>
      switch result {
      case .success(let value):
        future = self.eventLoop.makeSucceededFuture(value)
      case .failure(let error):
        future = self.eventLoop.makeFailedFuture(error)
      }
      self.state = .resolvedFuture(future)
      return future

    case .unresolvedPromise(let promise):
      return promise.futureResult

    case .resolvedFuture(let future):
      return future
    }
  }

  /// Succeed the promise with the given value.
  internal mutating func succeed(_ value: Value) {
    self.completeWith(.success(value))
  }

  /// Fail the promise with the given error.
  internal mutating func fail(_ error: Error) {
    self.completeWith(.failure(error))
  }

  /// Complete the promise with the given result.
  internal mutating func completeWith(_ result: Result<Value, Error>) {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case .idle:
      self.state = .resolvedResult(result)

    case .unresolvedPromise(let promise):
      promise.completeWith(result)
      self.state = .resolvedFuture(promise.futureResult)

    case .resolvedResult, .resolvedFuture:
      ()
    }
  }
}
