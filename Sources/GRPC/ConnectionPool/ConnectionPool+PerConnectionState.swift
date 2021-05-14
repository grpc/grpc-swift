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
  internal struct PerConnectionState {
    /// The connection manager for this connection.
    internal var manager: ConnectionManager

    /// Stream availability for this connection, `nil` if the connection is not available.
    private var availability: StreamAvailability?

    private struct StreamAvailability {
      var multiplexer: HTTP2StreamMultiplexer
      /// Maximum number of available streams.
      var maxAvailable: Int
      /// Number of streams reserved.
      var reserved: Int = 0
      /// Number of available streams.
      var available: Int {
        return self.maxAvailable - self.reserved
      }

      /// Increment the reserved streams and return the multiplexer.
      mutating func reserve() -> HTTP2StreamMultiplexer {
        self.reserved += 1
        return self.multiplexer
      }

      /// Decrement the reserved streams by one.
      mutating func `return`() {
        self.reserved -= 1
      }
    }

    init(manager: ConnectionManager) {
      self.manager = manager
      self.availability = nil
    }

    /// The number of reserved streams.
    internal var reservedStreams: Int {
      return self.availability?.reserved ?? 0
    }

    /// The number of streams available to reserve. If this value is greater than zero then it is
    /// safe to call `reserveStream()` and force unwrap the result.
    internal var availableStreams: Int {
      return self.availability?.available ?? 0
    }

    /// Reserve a stream and return the stream multiplexer. Returns `nil` if it is not possible
    /// to reserve a stream.
    ///
    /// The result may be safely unwrapped if `self.availableStreams > 0` when reserving a stream.
    internal mutating func reserveStream() -> HTTP2StreamMultiplexer? {
      return self.availability?.reserve()
    }

    /// Return a reserved stream to the connection.
    internal mutating func returnStream() {
      self.availability?.return()
    }

    internal mutating func updateMaxConcurrentStreams(_ maxConcurrentStreams: Int) {
      self.availability?.maxAvailable = maxConcurrentStreams
    }

    /// Mark the connection as available for reservation.
    internal mutating func available(maxConcurrentStreams: Int) {
      assert(self.availability == nil)

      self.availability = self.manager.sync.multiplexer.map {
        StreamAvailability(multiplexer: $0, maxAvailable: maxConcurrentStreams)
      }
    }

    /// Mark the connection as unavailable returning the number of reserved streams.
    internal mutating func unavailable() -> Int {
      defer {
        self.availability = nil
      }
      return self.availability?.reserved ?? 0
    }
  }
}
