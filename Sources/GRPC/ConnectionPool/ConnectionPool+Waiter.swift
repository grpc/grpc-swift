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
import NIO
import NIOHTTP2

extension ConnectionPool {
  internal final class Waiter {
    /// A promise to complete with the initialized channel.
    private let promise: EventLoopPromise<Channel>

    fileprivate var channelFuture: EventLoopFuture<Channel> {
      return self.promise.futureResult
    }

    /// The channel initializer.
    private let channelInitializer: (Channel) -> EventLoopFuture<Void>

    /// The deadline at which the timeout is scheduled.
    private let deadline: NIODeadline

    /// A scheduled task which fails the stream promise should the pool not provide
    /// a stream in time.
    private var scheduledTimeout: Scheduled<Void>?

    /// An identifier for this waiter.
    internal var id: ID {
      return ID(self)
    }

    internal init(
      deadline: NIODeadline,
      promise: EventLoopPromise<Channel>,
      channelInitializer: @escaping (Channel) -> EventLoopFuture<Void>
    ) {
      self.deadline = deadline
      self.promise = promise
      self.channelInitializer = channelInitializer
      self.scheduledTimeout = nil
    }

    /// Schedule a timeout for this waiter. This task will be cancelled when the waiter is
    /// succeeded or failed.
    ///
    /// - Parameters:
    ///   - eventLoop: The `EventLoop` to run the timeout task on.
    ///   - body: The closure to execute when the timeout is fired.
    internal func scheduleTimeout(
      on eventLoop: EventLoop,
      execute body: @escaping () -> Void
    ) {
      assert(self.scheduledTimeout == nil)
      eventLoop.scheduleTask(deadline: self.deadline, body)
    }

    /// Returns a boolean value indicating whether the deadline for this waiter occurs after the
    /// given deadline.
    internal func deadlineIsAfter(_ other: NIODeadline) -> Bool {
      return self.deadline > other
    }

    /// Succeed the waiter with the given multiplexer.
    internal func succeed(with multiplexer: HTTP2StreamMultiplexer) {
      self.scheduledTimeout?.cancel()
      self.scheduledTimeout = nil
      multiplexer.createStreamChannel(promise: self.promise, self.channelInitializer)
    }

    /// Fail the waiter with `error`.
    internal func fail(_ error: Error) {
      self.scheduledTimeout?.cancel()
      self.scheduledTimeout = nil
      self.promise.fail(error)
    }

    /// The ID of a waiter.
    internal struct ID: Hashable, CustomStringConvertible {
      private let id: ObjectIdentifier

      fileprivate init(_ waiter: Waiter) {
        self.id = ObjectIdentifier(waiter)
      }

      internal var description: String {
        return String(describing: self.id)
      }
    }
  }
}
