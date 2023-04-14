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
import NIOCore
import NIOHTTP2

extension ConnectionPool {
  @usableFromInline
  internal final class Waiter {
    /// A promise to complete with the initialized channel.
    @usableFromInline
    internal let _promise: EventLoopPromise<Channel>

    @usableFromInline
    internal var _channelFuture: EventLoopFuture<Channel> {
      return self._promise.futureResult
    }

    /// The channel initializer.
    @usableFromInline
    internal let _channelInitializer: @Sendable (Channel) -> EventLoopFuture<Void>

    /// The deadline at which the timeout is scheduled.
    @usableFromInline
    internal let _deadline: NIODeadline

    /// A scheduled task which fails the stream promise should the pool not provide
    /// a stream in time.
    @usableFromInline
    internal var _scheduledTimeout: Scheduled<Void>?

    /// An identifier for this waiter.
    @usableFromInline
    internal var id: ID {
      return ID(self)
    }

    @usableFromInline
    internal init(
      deadline: NIODeadline,
      promise: EventLoopPromise<Channel>,
      channelInitializer: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
    ) {
      self._deadline = deadline
      self._promise = promise
      self._channelInitializer = channelInitializer
      self._scheduledTimeout = nil
    }

    /// Schedule a timeout for this waiter. This task will be cancelled when the waiter is
    /// succeeded or failed.
    ///
    /// - Parameters:
    ///   - eventLoop: The `EventLoop` to run the timeout task on.
    ///   - body: The closure to execute when the timeout is fired.
    @usableFromInline
    internal func scheduleTimeout(
      on eventLoop: EventLoop,
      execute body: @escaping () -> Void
    ) {
      assert(self._scheduledTimeout == nil)
      self._scheduledTimeout = eventLoop.scheduleTask(deadline: self._deadline, body)
    }

    /// Returns a boolean value indicating whether the deadline for this waiter occurs after the
    /// given deadline.
    @usableFromInline
    internal func deadlineIsAfter(_ other: NIODeadline) -> Bool {
      return self._deadline > other
    }

    /// Succeed the waiter with the given multiplexer.
    @usableFromInline
    internal func succeed(with multiplexer: NIOHTTP2Handler.StreamMultiplexer) {
      self._scheduledTimeout?.cancel()
      self._scheduledTimeout = nil
      multiplexer.createStreamChannel(promise: self._promise, self._channelInitializer)
    }

    /// Fail the waiter with `error`.
    @usableFromInline
    internal func fail(_ error: Error) {
      self._scheduledTimeout?.cancel()
      self._scheduledTimeout = nil
      self._promise.fail(error)
    }

    /// The ID of a waiter.
    @usableFromInline
    internal struct ID: Hashable, CustomStringConvertible {
      @usableFromInline
      internal let _id: ObjectIdentifier

      @usableFromInline
      internal init(_ waiter: Waiter) {
        self._id = ObjectIdentifier(waiter)
      }

      @usableFromInline
      internal var description: String {
        return String(describing: self._id)
      }
    }
  }
}
