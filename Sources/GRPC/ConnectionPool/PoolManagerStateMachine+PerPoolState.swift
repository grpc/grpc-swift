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

extension PoolManagerStateMachine.ActiveState {
  internal struct EventLoopID: Hashable, CustomStringConvertible {
    private let id: ObjectIdentifier

    internal init(_ eventLoop: EventLoop) {
      self.id = ObjectIdentifier(eventLoop)
    }

    internal var description: String {
      return String(describing: self.id)
    }
  }

  internal struct PerPoolState {
    /// A pool of connections using the same `EventLoop`.
    internal var pool: ConnectionPool

    /// The number of streams reserved in the pool.
    internal private(set) var reservedStreams: Int

    /// The total number of streams which may be available in the pool.
    internal var maxAvailableStreams: Int

    /// The number of available streams.
    internal var availableStreams: Int {
      return self.maxAvailableStreams - self.reservedStreams
    }

    init(pool: ConnectionPool, assumedMaxAvailableStreams: Int) {
      self.pool = pool
      self.reservedStreams = 0
      self.maxAvailableStreams = assumedMaxAvailableStreams
    }

    /// Reserve a stream and return the pool.
    internal mutating func reserveStream() -> ConnectionPool {
      self.reservedStreams += 1
      return self.pool
    }

    /// Return a reserved stream.
    internal mutating func returnReservedStreams(_ count: Int) {
      self.reservedStreams -= count
      assert(self.reservedStreams >= 0)
    }
  }
}
