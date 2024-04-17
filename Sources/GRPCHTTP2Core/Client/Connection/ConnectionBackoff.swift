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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct ConnectionBackoff {
  var initial: Duration
  var max: Duration
  var multiplier: Double
  var jitter: Double

  init(initial: Duration, max: Duration, multiplier: Double, jitter: Double) {
    self.initial = initial
    self.max = max
    self.multiplier = multiplier
    self.jitter = jitter
  }

  func makeIterator() -> Iterator {
    return Iterator(self)
  }

  // Deliberately not conforming to `IteratorProtocol` as `next()` never returns `nil` which
  // isn't expressible via `IteratorProtocol`.
  struct Iterator {
    private var isInitial: Bool
    private var currentBackoffSeconds: Double

    private let jitter: Double
    private let multiplier: Double
    private let maxBackoffSeconds: Double

    init(_ backoff: ConnectionBackoff) {
      self.isInitial = true
      self.currentBackoffSeconds = Self.seconds(from: backoff.initial)
      self.jitter = backoff.jitter
      self.multiplier = backoff.multiplier
      self.maxBackoffSeconds = Self.seconds(from: backoff.max)
    }

    private static func seconds(from duration: Duration) -> Double {
      var seconds = Double(duration.components.seconds)
      seconds += Double(duration.components.attoseconds) / 1e18
      return seconds
    }

    private static func duration(from seconds: Double) -> Duration {
      let nanoseconds = seconds * 1e9
      let wholeNanos = Int64(nanoseconds)
      return .nanoseconds(wholeNanos)
    }

    mutating func next() -> Duration {
      // The initial backoff doesn't get jittered.
      if self.isInitial {
        self.isInitial = false
        return Self.duration(from: self.currentBackoffSeconds)
      }

      // Scale up the last backoff.
      self.currentBackoffSeconds *= self.multiplier

      // Limit it to the max backoff.
      if self.currentBackoffSeconds > self.maxBackoffSeconds {
        self.currentBackoffSeconds = self.maxBackoffSeconds
      }

      let backoff = self.currentBackoffSeconds
      let jitter = Double.random(in: -(self.jitter * backoff) ... self.jitter * backoff)
      let jitteredBackoff = backoff + jitter

      return Self.duration(from: jitteredBackoff)
    }
  }
}
