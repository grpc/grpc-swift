/*
 * Copyright 2023, gRPC Authors All rights reserved.
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
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@usableFromInline
struct RetryDelaySequence: Sequence {
  @usableFromInline
  typealias Element = Duration

  @usableFromInline
  let policy: RetryPolicy

  @inlinable
  init(policy: RetryPolicy) {
    self.policy = policy
  }

  @inlinable
  func makeIterator() -> Iterator {
    Iterator(policy: self.policy)
  }

  @usableFromInline
  struct Iterator: IteratorProtocol {
    @usableFromInline
    let policy: RetryPolicy
    @usableFromInline
    private(set) var n = 1

    @inlinable
    init(policy: RetryPolicy) {
      self.policy = policy
    }

    @inlinable
    var _initialBackoffSeconds: Double {
      Self._durationToTimeInterval(self.policy.initialBackoff)
    }

    @inlinable
    var _maximumBackoffSeconds: Double {
      Self._durationToTimeInterval(self.policy.maximumBackoff)
    }

    @inlinable
    mutating func next() -> Duration? {
      defer { self.n += 1 }

      /// The nth retry will happen after a randomly chosen delay between zero and
      /// `min(initialBackoff * backoffMultiplier^(n-1), maximumBackoff)`.
      let factor = pow(self.policy.backoffMultiplier, Double(self.n - 1))
      let computedBackoff = self._initialBackoffSeconds * factor
      let clampedBackoff = Swift.min(computedBackoff, self._maximumBackoffSeconds)
      let randomisedBackoff = Double.random(in: 0.0 ... clampedBackoff)

      return Self._timeIntervalToDuration(randomisedBackoff)
    }

    @inlinable
    static func _timeIntervalToDuration(_ seconds: Double) -> Duration {
      let secondsComponent = Int64(seconds)
      let attoseconds = (seconds - Double(secondsComponent)) * 1e18
      let attosecondsComponent = Int64(attoseconds)
      return Duration(
        secondsComponent: secondsComponent,
        attosecondsComponent: attosecondsComponent
      )
    }

    @inlinable
    static func _durationToTimeInterval(_ duration: Duration) -> Double {
      var seconds = Double(duration.components.seconds)
      seconds += (Double(duration.components.attoseconds) / 1e18)
      return seconds
    }
  }
}
