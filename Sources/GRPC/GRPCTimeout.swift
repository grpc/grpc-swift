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
import Dispatch
import NIOCore

/// A timeout for a gRPC call.
///
/// Timeouts must be positive and at most 8-digits long.
public struct GRPCTimeout: CustomStringConvertible, Equatable {
  /// Creates an infinite timeout. This is a sentinel value which must __not__ be sent to a gRPC service.
  public static let infinite = GRPCTimeout(
    nanoseconds: Int64.max,
    wireEncoding: "infinite"
  )

  /// The largest amount of any unit of time which may be represented by a gRPC timeout.
  internal static let maxAmount: Int64 = 99_999_999

  /// The wire encoding of this timeout as described in the gRPC protocol.
  /// See: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md.
  public let wireEncoding: String
  public let nanoseconds: Int64

  public var description: String {
    return self.wireEncoding
  }

  /// Creates a timeout from the given deadline.
  ///
  /// - Parameter deadline: The deadline to create a timeout from.
  internal init(deadline: NIODeadline, testingOnlyNow: NIODeadline? = nil) {
    switch deadline {
    case .distantFuture:
      self = .infinite
    default:
      let timeAmountUntilDeadline = deadline - (testingOnlyNow ?? .now())
      self.init(rounding: timeAmountUntilDeadline.nanoseconds, unit: .nanoseconds)
    }
  }

  private init(nanoseconds: Int64, wireEncoding: String) {
    self.nanoseconds = nanoseconds
    self.wireEncoding = wireEncoding
  }

  /// Creates a `GRPCTimeout`.
  ///
  /// - Precondition: The amount should be greater than or equal to zero and less than or equal
  ///   to `GRPCTimeout.maxAmount`.
  internal init(amount: Int64, unit: GRPCTimeoutUnit) {
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
  internal init(rounding amount: Int64, unit: GRPCTimeoutUnit) {
    var roundedAmount = amount
    var roundedUnit = unit

    if roundedAmount <= 0 {
      roundedAmount = 0
    } else {
      while roundedAmount > GRPCTimeout.maxAmount {
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
          roundedAmount = GRPCTimeout.maxAmount
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

internal enum GRPCTimeoutUnit: String {
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
