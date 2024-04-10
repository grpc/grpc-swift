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

import Foundation
import GRPCCore
import NIOConcurrencyHelpers

/// Stores the real time latency histogram and error code count dictionary,
/// for the RPCs made by a particular GRPCClient. It gets updated after
/// each finished RPC.
///
/// The time latency is measured in nanoseconds.
struct RPCStats {
  var latencyHistogram: LatencyHistogram
  var requestResultCount: [RPCError.Code: Int64]

  init(latencyHistogram: LatencyHistogram, requestResultCount: [RPCError.Code: Int64] = [:]) {
    self.latencyHistogram = latencyHistogram
    self.requestResultCount = requestResultCount
  }

  /// Histograms are stored with exponentially increasing bucket sizes.
  /// The first bucket is [0, `multiplier`) where `multiplier` = 1 + resolution
  /// Bucket n (n>=1) contains [`multiplier`**n, `multiplier`**(n+1))
  /// There are sufficient buckets to reach max_bucket_start
  struct LatencyHistogram {
    var sum: Double
    var sumOfSquares: Double
    var countOfValuesSeen: Double
    var multiplier: Double
    var oneOnLogMultiplier: Double
    var minSeen: Double
    var maxSeen: Double
    var maxPossible: Double
    var buckets: [UInt32]

    /// Initialise a histogram.
    /// - parameters:
    ///     - resolution: Defines the width of the buckets - see the description of this structure.
    ///     - maxBucketStart: Defines the start of the greatest valued bucket.
    init(resolution: Double = 0.01, maxBucketStart: Double = 60e9) {
      precondition(resolution > 0.0)
      precondition(maxBucketStart > resolution)
      self.sum = 0.0
      self.sumOfSquares = 0.0
      self.multiplier = 1.0 + resolution
      self.oneOnLogMultiplier = 1.0 / log(1.0 + resolution)
      self.maxPossible = maxBucketStart
      self.countOfValuesSeen = 0.0
      self.minSeen = maxBucketStart
      self.maxSeen = 0.0
      let numBuckets =
        LatencyHistogram.uncheckedBucket(
          forValue: maxBucketStart,
          oneOnLogMultiplier: self.oneOnLogMultiplier
        ) + 1
      precondition(numBuckets > 1)
      precondition(numBuckets < 100_000_000)
      self.buckets = .init(repeating: 0, count: numBuckets)
    }

    struct HistorgramShapeMismatch: Error {}

    /// Determine a bucket index given a value - does no bounds checking
    private static func uncheckedBucket(forValue value: Double, oneOnLogMultiplier: Double) -> Int {
      return Int(log(value) * oneOnLogMultiplier)
    }

    private func bucket(forValue value: Double) -> Int {
      let bucket = LatencyHistogram.uncheckedBucket(
        forValue: min(self.maxPossible, max(0, value)),
        oneOnLogMultiplier: self.oneOnLogMultiplier
      )
      assert(bucket < self.buckets.count)
      assert(bucket >= 0)
      return bucket
    }

    /// Add a value to this histogram, updating buckets and stats
    /// - parameters:
    ///     - value: The value to add.
    public mutating func record(_ value: Double) {
      self.sum += value
      self.sumOfSquares += value * value
      self.countOfValuesSeen += 1
      if value < self.minSeen {
        self.minSeen = value
      }
      if value > self.maxSeen {
        self.maxSeen = value
      }
      self.buckets[self.bucket(forValue: value)] += 1
    }

    /// Merge two histograms together updating `self`
    /// - parameters:
    ///    - source: the other histogram to merge into this.
    public mutating func merge(_ other: LatencyHistogram) throws {
      guard (self.buckets.count == other.buckets.count) || (self.multiplier == other.multiplier)
      else {
        // Fail because these histograms don't match.
        throw HistorgramShapeMismatch()
      }

      self.sum += other.sum
      self.sumOfSquares += other.sumOfSquares
      self.countOfValuesSeen += other.countOfValuesSeen
      if other.minSeen < self.minSeen {
        self.minSeen = other.minSeen
      }
      if other.maxSeen > self.maxSeen {
        self.maxSeen = other.maxSeen
      }
      for bucket in 0 ..< self.buckets.count {
        self.buckets[bucket] += other.buckets[bucket]
      }
    }
  }
}
