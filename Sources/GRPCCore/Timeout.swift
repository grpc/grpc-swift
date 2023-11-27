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
import Dispatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A timeout for a gRPC call.
///
/// It's a combination of an amount (expressed as an integer of at maximum 8 digits), and a unit, which is
/// one of ``Timeout/Unit`` (hours, minutes, seconds, milliseconds, microseconds or nanoseconds).
///
/// Timeouts must be positive and at most 8-digits long.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@usableFromInline
struct Timeout: CustomStringConvertible, Hashable, Sendable {
  /// Possible units for a ``Timeout``.
  internal enum Unit: Character {
    case hours = "H"
    case minutes = "M"
    case seconds = "S"
    case milliseconds = "m"
    case microseconds = "u"
    case nanoseconds = "n"
  }

  /// The largest amount of any unit of time which may be represented by a gRPC timeout.
  static let maxAmount: Int64 = 99_999_999

  /// The wire encoding of this timeout as described in the gRPC protocol.
  /// See "Timeout" in https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests
  let wireEncoding: String

  @usableFromInline
  let duration: Duration

  @usableFromInline
  var description: String {
    return self.wireEncoding
  }

  @usableFromInline
  init?(stringLiteral value: String) {
      guard (2 ... 8).contains(value.count) else {
      return nil
    }

    if let amount = Int64(value.dropLast()),
      let unit = Unit(rawValue: value.last!)
    {
      self = Self.init(amount: amount, unit: unit)
    } else {
      return nil
    }
  }

  /// Create a ``Timeout`` from a ``Duration``.
  ///
  /// - Important: It's not possible to know with what precision the duration was created: that is,
  /// it's not possible to know whether `Duration.seconds(value)` or `Duration.milliseconds(value)`
  /// was used. For this reason, the unit chosen for the ``Timeout`` (and thus the wire encoding) may be
  /// different from the one originally used to create the ``Duration``. Despite this, we guarantee that
  /// both durations will be equivalent.
  /// For example, `Duration.hours(123)` will yield a ``Timeout`` with `wireEncoding` equal to
  /// `"442800S"`, which is in seconds. However, 442800 seconds and 123 hours are equivalent.
  @usableFromInline
  init(duration: Duration) {
    let (seconds, attoseconds) = duration.components

    if seconds == 0 {
      // There is no seconds component, so only pay attention to the attoseconds.
      // Try converting to nanoseconds first...
      let nanoseconds = Int64(round(Double(attoseconds) / 1e+9))
      if Self.exceedsDigitLimit(nanoseconds) {
        // If the number of digits exceeds the max (8), try microseconds.
        let microseconds = nanoseconds / 1000

        // The max value for attoseconds, as per `Duration`'s docs is 1e+18.
        // This means that, after dividing by 1e+9 and later by 1000 (1e+3),
        // the max number of digits will be those in 1e+18 / 1e+12 = 1e+6 = 1.000.000
        // -> 7 digits. We don't need to check anymore and can represent this
        // value as microseconds.
        self.init(amount: microseconds, unit: .microseconds)
      } else {
        self.init(amount: nanoseconds, unit: .nanoseconds)
      }
    } else {
      if Self.exceedsDigitLimit(seconds) {
        // We don't have enough digits to represent this amount in seconds, so
        // we will have to use minutes or hours.
        // We can also ignore attoseconds, since we won't have enough precision
        // anyways to represent the (at most) one second that the attoseconds
        // component can express.

        // Try with minutes first...
        let minutes = seconds / 60
        if Self.exceedsDigitLimit(minutes) {
          // We don't have enough digits to represent the amount using minutes.
          // Try hours...
          let hours = minutes / 60
          if Self.exceedsDigitLimit(hours) {
            // We don't have enough digits to represent the amount using hours.
            // Then initialize the timeout to the maximum possible value.
            self.init(amount: Timeout.maxAmount, unit: .hours)
          } else {
            self.init(amount: hours, unit: .hours)
          }
        } else {
          self.init(amount: minutes, unit: .minutes)
        }
      } else {
        // We can't convert seconds to nanoseconds because that would take us
        // over the 8 digit limit (1 second = 1e+9 nanoseconds).
        // We can however, try converting to microseconds or milliseconds.
        let nanoseconds = Int64(Double(attoseconds) / 1e+9)
        let microseconds = nanoseconds / 1000

        if microseconds == 0 {
          self.init(amount: seconds, unit: .seconds)
        } else {
          let secondsInMicroseconds = seconds * 1000 * 1000
          let totalMicroseconds = microseconds + secondsInMicroseconds
          if Self.exceedsDigitLimit(totalMicroseconds) {
            let totalMilliseconds = totalMicroseconds / 1000
            if Self.exceedsDigitLimit(totalMilliseconds) {
              let totalSeconds = totalMicroseconds / 1000
              self.init(amount: totalSeconds, unit: .seconds)
            } else {
              self.init(amount: totalMilliseconds, unit: .milliseconds)
            }
          } else {
            self.init(amount: totalMicroseconds, unit: .microseconds)
          }
        }
      }
    }
  }

  private static func exceedsDigitLimit(_ value: Int64) -> Bool {
    (value == 0 ? 1 : floor(log10(Double(value))) + 1) > 8
  }

  /// Creates a `GRPCTimeout`.
  ///
  /// - Precondition: The amount should be greater than or equal to zero and less than or equal
  ///   to `GRPCTimeout.maxAmount`.
  internal init(amount: Int64, unit: Unit) {
    precondition((0 ... Timeout.maxAmount).contains(amount))

    self.duration = Duration(amount: amount, unit: unit)
    self.wireEncoding = "\(amount)\(unit.rawValue)"
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Duration {
  /// Construct a `Duration` given a number of minutes represented as an `Int64`.
  ///
  ///       let d: Duration = .minutes(5)
  ///
  /// - Returns: A `Duration` representing a given number of minutes.
  internal static func minutes(_ minutes: Int64) -> Duration {
    return Self.init(secondsComponent: 60 * minutes, attosecondsComponent: 0)
  }

  /// Construct a `Duration` given a number of hours represented as an `Int64`.
  ///
  ///       let d: Duration = .hours(3)
  ///
  /// - Returns: A `Duration` representing a given number of hours.
  internal static func hours(_ hours: Int64) -> Duration {
    return Self.init(secondsComponent: 60 * 60 * hours, attosecondsComponent: 0)
  }

  internal init(amount: Int64, unit: Timeout.Unit) {
    switch unit {
    case .hours:
      self = Self.hours(amount)
    case .minutes:
      self = Self.minutes(amount)
    case .seconds:
      self = Self.seconds(amount)
    case .milliseconds:
      self = Self.milliseconds(amount)
    case .microseconds:
      self = Self.microseconds(amount)
    case .nanoseconds:
      self = Self.nanoseconds(amount)
    }
  }
}
