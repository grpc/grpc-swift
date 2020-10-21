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

import BenchmarkUtils
import NIOConcurrencyHelpers

/// Convenience holder for collected statistics.
struct Stats {
  /// Latency statistics.
  var latencies = Histogram()
  /// Error status counts.
  var statuses = StatusCounts()
}

/// Stats with access controlled by a lock -
/// Needs locking rather than event loop hopping as the driver refuses to wait shutting
/// the connection immediately after the request.
class StatsWithLock {
  private var data = Stats()
  private let lock = Lock()

  /// Record a latency value into the stats.
  /// - parameters:
  ///     - latency: The value to record.
  func add(latency: Double) {
    self.lock.withLockVoid { self.data.latencies.add(value: latency) }
  }

  func add(latency: Nanoseconds) {
    self.add(latency: Double(latency.value))
  }

  /// Copy the data out.
  /// - parameters:
  ///     - reset: If the statistics should be reset after collection or not.
  /// - returns: A copy of the statistics.
  func copyData(reset: Bool) -> Stats {
    return self.lock.withLock {
      let result = self.data
      if reset {
        self.data = Stats()
      }
      return result
    }
  }
}
