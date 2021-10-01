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

extension PoolManagerStateMachine.ActiveState {
  @usableFromInline
  internal struct PerPoolState {
    /// The index of the connection pool associated with this state.
    @usableFromInline
    internal var poolIndex: PoolManager.ConnectionPoolIndex

    /// The number of streams reserved in the pool.
    @usableFromInline
    internal private(set) var reservedStreams: Int

    /// The total number of streams which may be available in the pool.
    @usableFromInline
    internal var maxAvailableStreams: Int

    /// The number of available streams.
    @usableFromInline
    internal var availableStreams: Int {
      return self.maxAvailableStreams - self.reservedStreams
    }

    @usableFromInline
    init(poolIndex: PoolManager.ConnectionPoolIndex, assumedMaxAvailableStreams: Int) {
      self.poolIndex = poolIndex
      self.reservedStreams = 0
      self.maxAvailableStreams = assumedMaxAvailableStreams
    }

    /// Reserve a stream and return the pool.
    @usableFromInline
    internal mutating func reserveStream() -> PoolManager.ConnectionPoolIndex {
      self.reservedStreams += 1
      return self.poolIndex
    }

    /// Return a reserved stream.
    @usableFromInline
    internal mutating func returnReservedStreams(_ count: Int) {
      self.reservedStreams -= count
      assert(self.reservedStreams >= 0)
    }
  }
}

extension PoolManager {
  @usableFromInline
  internal struct ConnectionPoolIndex: Hashable {
    @usableFromInline
    var value: Int

    @usableFromInline
    init(_ value: Int) {
      self.value = value
    }
  }

  @usableFromInline
  internal struct ConnectionPoolKey: Hashable {
    /// The index of the connection pool.
    @usableFromInline
    var index: ConnectionPoolIndex

    /// The ID of the`EventLoop` the connection pool uses.
    @usableFromInline
    var eventLoopID: EventLoopID
  }
}

@usableFromInline
internal struct EventLoopID: Hashable, CustomStringConvertible {
  @usableFromInline
  internal let _id: ObjectIdentifier

  @usableFromInline
  internal init(_ eventLoop: EventLoop) {
    self._id = ObjectIdentifier(eventLoop)
  }

  @usableFromInline
  internal var description: String {
    return String(describing: self._id)
  }
}

extension EventLoop {
  @usableFromInline
  internal var id: EventLoopID {
    return EventLoopID(self)
  }
}
