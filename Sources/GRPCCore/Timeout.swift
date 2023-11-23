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

/// A timeout for a gRPC call.
///
/// Timeouts must be positive and at most 8-digits long.
/// See "Timeout" in https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct Timeout: CustomStringConvertible, Equatable {
  /// The largest amount of any unit of time which may be represented by a gRPC timeout.
  internal static let maxAmount: Int64 = 99_999_999

  /// The wire encoding of this timeout as described in the gRPC protocol.
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md.
  public let wireEncoding: String
  public let duration: Duration

  public var description: String {
    return self.wireEncoding
  }

  public init?(stringLiteral value: String) {
    guard 2 ... 8 ~= value.count else {
      return nil
    }

    if let amount = Int64(value.dropLast()),
      let unit = TimeoutUnit(rawValue: value.last!)
    {
      self = Self.init(amount: amount, unit: unit)
    } else {
      return nil
    }
  }

  /// Creates a `GRPCTimeout`.
  ///
  /// - Precondition: The amount should be greater than or equal to zero and less than or equal
  ///   to `GRPCTimeout.maxAmount`.
  internal init(amount: Int64, unit: TimeoutUnit) {
    precondition(0 ... Timeout.maxAmount ~= amount)

    self.duration = Duration(amount: amount, unit: unit)
    self.wireEncoding = "\(amount)\(unit.rawValue)"
  }

  /// Create a timeout by rounding up the timeout so that it may be represented in the gRPC
  /// wire format.
  internal init(rounding amount: Int64, unit: TimeoutUnit) {
    var roundedAmount = amount
    var roundedUnit = unit

    if roundedAmount <= 0 {
      roundedAmount = 0
    } else {
      while roundedAmount > Timeout.maxAmount {
        switch roundedUnit {
        case .nanoseconds:
          roundedAmount = roundedAmount.quotientRoundedUp(dividingBy: 1000)
          roundedUnit = .microseconds
        case .microseconds:
          roundedAmount = roundedAmount.quotientRoundedUp(dividingBy: 1000)
          roundedUnit = .milliseconds
        case .milliseconds:
          roundedAmount = roundedAmount.quotientRoundedUp(dividingBy: 1000)
          roundedUnit = .seconds
        case .seconds:
          roundedAmount = roundedAmount.quotientRoundedUp(dividingBy: 60)
          roundedUnit = .minutes
        case .minutes:
          roundedAmount = roundedAmount.quotientRoundedUp(dividingBy: 60)
          roundedUnit = .hours
        case .hours:
          roundedAmount = Timeout.maxAmount
          roundedUnit = .hours
        }
      }
    }

    self.init(amount: roundedAmount, unit: roundedUnit)
  }
}

extension Int64 {
  /// Returns the quotient of this value when divided by `divisor` rounded up to the nearest
  /// multiple of `divisor` if the remainder is non-zero.
  ///
  /// - Parameter divisor: The value to divide this value by.
  fileprivate func quotientRoundedUp(dividingBy divisor: Int64) -> Int64 {
    let (quotient, remainder) = self.quotientAndRemainder(dividingBy: divisor)
    return quotient + (remainder != 0 ? 1 : 0)
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

  internal init(amount: Int64, unit: TimeoutUnit) {
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

internal enum TimeoutUnit: Character {
  case hours = "H"
  case minutes = "M"
  case seconds = "S"
  case milliseconds = "m"
  case microseconds = "u"
  case nanoseconds = "n"
}
