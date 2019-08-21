/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import NIO

public enum GRPCTimeoutError: String, Error, Equatable {
  case negative = "GRPCTimeout must be non-negative"
  case tooManyDigits = "GRPCTimeout must be at most 8 digits"
}

/// A timeout for a gRPC call.
///
/// Timeouts must be positive and at most 8-digits long.
public struct GRPCTimeout: CustomStringConvertible, Equatable {
  public static let `default`: GRPCTimeout = try! .minutes(1)
  /// Creates an infinite timeout. This is a sentinel value which must __not__ be sent to a gRPC service.
  public static let infinite: GRPCTimeout = GRPCTimeout(nanoseconds: Int64.max, wireEncoding: "infinite")

  /// The largest amount of any unit of time which may be represented by a gRPC timeout.
  private static let maxAmount: Int64 = 99_999_999

  /// The wire encoding of this timeout as described in the gRPC protocol.
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md.
  public let wireEncoding: String
  public let nanoseconds: Int64

  public var description: String {
    return wireEncoding
  }

  private init(nanoseconds: Int64, wireEncoding: String) {
    self.nanoseconds = nanoseconds
    self.wireEncoding = wireEncoding
  }

  /// Creates a `GRPCTimeout`.
  ///
  /// - Precondition: The amount should be greater than or equal to zero and less than or equal
  ///   to `GRPCTimeout.maxAmount`.
  private init(amount: Int64, unit: GRPCTimeoutUnit) {
    precondition(amount >= 0 && amount <= GRPCTimeout.maxAmount)
    // See "Timeout" in https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests

    // If we overflow at this point, which is certainly possible if `amount` is sufficiently large
    // and `unit` is `.hours`, clamp the nanosecond timeout to `Int64.max`. It's about 292 years so
    // it should be long enough for the user not to notice the difference should the rpc time out.
    let (partial, overflow) = amount.multipliedReportingOverflow(by: unit.asNanoseconds)

    self.init(
      nanoseconds: overflow ? Int64.max : partial,
      wireEncoding: "\(amount)\(unit.rawValue)"
    )
  }

  /// Create a timeout by rounding up the timeout so that it may be represented in the gRPC
  /// wire format.
  private init(rounding amount: Int64, unit: GRPCTimeoutUnit) {
    var roundedAmount = amount
    var roundedUnit = unit

    if roundedAmount <= 0 {
      roundedAmount = 0
    } else {
      while roundedAmount > GRPCTimeout.maxAmount {
        switch roundedUnit {
        case .nanoseconds:
          roundedAmount = roundedAmount.quotientRoundedUp(dividingBy: 1_000)
          roundedUnit = .microseconds
        case .microseconds:
          roundedAmount = roundedAmount.quotientRoundedUp(dividingBy: 1_000)
          roundedUnit = .milliseconds
        case .milliseconds:
          roundedAmount = roundedAmount.quotientRoundedUp(dividingBy: 1_000)
          roundedUnit = .seconds
        case .seconds:
          roundedAmount = roundedAmount.quotientRoundedUp(dividingBy: 60)
          roundedUnit = .minutes
        case .minutes:
          roundedAmount = roundedAmount.quotientRoundedUp(dividingBy: 60)
          roundedUnit = .hours
        case .hours:
          roundedAmount = GRPCTimeout.maxAmount
          roundedUnit = .hours
        }
      }
    }

    self.init(amount: roundedAmount, unit: roundedUnit)
  }

  private static func makeTimeout(_ amount: Int64, _ unit: GRPCTimeoutUnit) throws -> GRPCTimeout {
    // Timeouts must be positive and at most 8-digits.
    if amount < 0 {
      throw GRPCTimeoutError.negative
    }
    if amount > GRPCTimeout.maxAmount {
      throw GRPCTimeoutError.tooManyDigits
    }
    return .init(amount: amount, unit: unit)
  }

  /// Creates a new GRPCTimeout for the given amount of hours.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of hours this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of hours.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func hours(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(Int64(amount), .hours)
  }

  /// Creates a new GRPCTimeout for the given amount of hours.
  ///
  /// The timeout will be rounded up if it may not be represented in the wire format.
  ///
  /// - Parameter amount: The number of hours to represent.
  public static func hours(rounding amount: Int) -> GRPCTimeout {
    return .init(rounding: Int64(amount), unit: .hours)
  }

  /// Creates a new GRPCTimeout for the given amount of minutes.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of minutes this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of minutes.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func minutes(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(Int64(amount), .minutes)
  }

  /// Creates a new GRPCTimeout for the given amount of minutes.
  ///
  /// The timeout will be rounded up if it may not be represented in the wire format.
  ///
  /// - Parameter amount: The number of minutes to represent.
  public static func minutes(rounding amount: Int) -> GRPCTimeout {
    return .init(rounding: Int64(amount), unit: .minutes)
  }

  /// Creates a new GRPCTimeout for the given amount of seconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of seconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of seconds.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func seconds(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(Int64(amount), .seconds)
  }

  /// Creates a new GRPCTimeout for the given amount of seconds.
  ///
  /// The timeout will be rounded up if it may not be represented in the wire format.
  ///
  /// - Parameter amount: The number of seconds to represent.
  public static func seconds(rounding amount: Int) -> GRPCTimeout {
    return .init(rounding: Int64(amount), unit: .seconds)
  }

  /// Creates a new GRPCTimeout for the given amount of milliseconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of milliseconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of milliseconds.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func milliseconds(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(Int64(amount), .milliseconds)
  }

  /// Creates a new GRPCTimeout for the given amount of milliseconds.
  ///
  /// The timeout will be rounded up if it may not be represented in the wire format.
  ///
  /// - Parameter amount: The number of milliseconds to represent.
  public static func milliseconds(rounding amount: Int) -> GRPCTimeout {
    return .init(rounding: Int64(amount), unit: .milliseconds)
  }

  /// Creates a new GRPCTimeout for the given amount of microseconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of microseconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of microseconds.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func microseconds(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(Int64(amount), .microseconds)
  }

  /// Creates a new GRPCTimeout for the given amount of microseconds.
  ///
  /// The timeout will be rounded up if it may not be represented in the wire format.
  ///
  /// - Parameter amount: The number of microseconds to represent.
  public static func microseconds(rounding amount: Int) -> GRPCTimeout {
    return .init(rounding: Int64(amount), unit: .microseconds)
  }

  /// Creates a new GRPCTimeout for the given amount of nanoseconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of nanoseconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of nanoseconds.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func nanoseconds(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(Int64(amount), .nanoseconds)
  }

  /// Creates a new GRPCTimeout for the given amount of nanoseconds.
  ///
  /// The timeout will be rounded up if it may not be represented in the wire format.
  ///
  /// - Parameter amount: The number of nanoseconds to represent.
  public static func nanoseconds(rounding amount: Int) -> GRPCTimeout {
    return .init(rounding: Int64(amount), unit: .nanoseconds)
  }
}

public extension GRPCTimeout {
  /// Returns a NIO `TimeAmount` representing the amount of time as this timeout.
  var asNIOTimeAmount: TimeAmount {
    return TimeAmount.nanoseconds(numericCast(nanoseconds))
  }
}

fileprivate extension Int64 {
  /// Returns the quotient of this value when divided by `divisor` rounded up to the nearest
  /// multiple of `divisor` if the remainder is non-zero.
  ///
  /// - Parameter divisor: The value to divide this value by.
  func quotientRoundedUp(dividingBy divisor: Int64) -> Int64 {
    let (quotient, remainder) = self.quotientAndRemainder(dividingBy: divisor)
    return quotient + (remainder != 0 ? 1 : 0)
  }
}

fileprivate enum GRPCTimeoutUnit: String {
  case hours = "H"
  case minutes = "M"
  case seconds = "S"
  case milliseconds = "m"
  case microseconds = "u"
  case nanoseconds = "n"

  internal var asNanoseconds: Int64 {
    switch self {
    case .hours:
      return 60 * 60 * 1000 * 1000 * 1000

    case .minutes:
      return 60 * 1000 * 1000 * 1000

    case .seconds:
      return 1000 * 1000 * 1000

    case .milliseconds:
      return 1000 * 1000

    case .microseconds:
      return 1000

    case .nanoseconds:
      return 1
    }
  }
}
