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
import NIOHTTP2

extension ConnectionPool {
  @usableFromInline
  internal struct PerConnectionState {
    /// The connection manager for this connection.
    @usableFromInline
    internal var manager: ConnectionManager

    /// Stream availability for this connection, `nil` if the connection is not available.
    @usableFromInline
    internal var _availability: StreamAvailability?

    @usableFromInline
    internal var isQuiescing: Bool {
      get {
        return self._availability?.isQuiescing ?? false
      }
      set {
        self._availability?.isQuiescing = true
      }
    }

    @usableFromInline
    internal struct StreamAvailability {
      @usableFromInline
      struct Utilization {
        @usableFromInline
        var used: Int
        @usableFromInline
        var capacity: Int

        @usableFromInline
        init(used: Int, capacity: Int) {
          self.used = used
          self.capacity = capacity
        }
      }

      @usableFromInline
      var multiplexer: HTTP2StreamMultiplexer
      /// Maximum number of available streams.
      @usableFromInline
      var maxAvailable: Int
      /// Number of streams reserved.
      @usableFromInline
      var reserved: Int = 0
      /// Number of streams opened.
      @usableFromInline
      var open: Int = 0
      @usableFromInline
      var isQuiescing = false
      /// Number of available streams.
      @usableFromInline
      var available: Int {
        return self.isQuiescing ? 0 : self.maxAvailable - self.reserved
      }

      /// Increment the reserved streams and return the multiplexer.
      @usableFromInline
      mutating func reserve() -> HTTP2StreamMultiplexer {
        assert(!self.isQuiescing)
        self.reserved += 1
        return self.multiplexer
      }

      @usableFromInline
      mutating func opened() -> Utilization {
        self.open += 1
        return .init(used: self.open, capacity: self.maxAvailable)
      }

      /// Decrement the reserved streams by one.
      @usableFromInline
      mutating func `return`() -> Utilization {
        self.reserved -= 1
        self.open -= 1
        assert(self.reserved >= 0)
        assert(self.open >= 0)
        return .init(used: self.open, capacity: self.maxAvailable)
      }
    }

    @usableFromInline
    init(manager: ConnectionManager) {
      self.manager = manager
      self._availability = nil
    }

    /// The number of reserved streams.
    @usableFromInline
    internal var reservedStreams: Int {
      return self._availability?.reserved ?? 0
    }

    /// The number of streams available to reserve. If this value is greater than zero then it is
    /// safe to call `reserveStream()` and force unwrap the result.
    @usableFromInline
    internal var availableStreams: Int {
      return self._availability?.available ?? 0
    }

    /// The maximum number of concurrent streams which may be available for the connection, if it
    /// is ready.
    @usableFromInline
    internal var maxAvailableStreams: Int? {
      return self._availability?.maxAvailable
    }

    /// Reserve a stream and return the stream multiplexer. Returns `nil` if it is not possible
    /// to reserve a stream.
    ///
    /// The result may be safely unwrapped if `self.availableStreams > 0` when reserving a stream.
    @usableFromInline
    internal mutating func reserveStream() -> HTTP2StreamMultiplexer? {
      return self._availability?.reserve()
    }

    @usableFromInline
    internal mutating func openedStream() -> PerConnectionState.StreamAvailability.Utilization? {
      return self._availability?.opened()
    }

    /// Return a reserved stream to the connection.
    @usableFromInline
    internal mutating func returnStream() -> PerConnectionState.StreamAvailability.Utilization? {
      return self._availability?.return()
    }

    /// Update the maximum concurrent streams available on the connection, marking it as available
    /// if it was not already.
    ///
    /// Returns the previous value for max concurrent streams if the connection was ready.
    @usableFromInline
    internal mutating func updateMaxConcurrentStreams(_ maxConcurrentStreams: Int) -> Int? {
      if var availability = self._availability {
        var oldValue = maxConcurrentStreams
        swap(&availability.maxAvailable, &oldValue)
        self._availability = availability
        return oldValue
      } else {
        self._availability = self.manager.sync.multiplexer.map {
          StreamAvailability(multiplexer: $0, maxAvailable: maxConcurrentStreams)
        }
        return nil
      }
    }

    /// Mark the connection as unavailable returning the number of reserved streams.
    @usableFromInline
    internal mutating func unavailable() -> Int {
      defer {
        self._availability = nil
      }
      return self._availability?.reserved ?? 0
    }
  }
}
