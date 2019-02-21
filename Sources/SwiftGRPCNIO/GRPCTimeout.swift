import Foundation
import NIO

public enum GRPCTimeoutError: String, Error {
  case negative = "GRPCTimeout must be non-negative"
  case tooManyDigits = "GRPCTimeout must be at most 8 digits"
}

/// A timeout for a gRPC call.
///
/// Timeouts must be positive and at most 8-digits long.
public struct GRPCTimeout: CustomStringConvertible, Equatable {
  public static let `default`: GRPCTimeout = try! .minutes(1)
  /// Creates an infinite timeout. This is a sentinel value which must __not__ be sent to a gRPC service.
  public static let infinite: GRPCTimeout = GRPCTimeout(nanoseconds: Int64.max, description: "infinite")

  /// A description of the timeout in the format described in the
  /// [gRPC protocol](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md).
  public let description: String
  public let nanoseconds: Int64

  private init(nanoseconds: Int64, description: String) {
    self.nanoseconds = nanoseconds
    self.description = description
  }

  private static func makeTimeout(_ amount: Int, _ unit: GRPCTimeoutUnit) throws -> GRPCTimeout {
    // Timeouts must be positive and at most 8-digits.
    if amount < 0 { throw GRPCTimeoutError.negative }
    if amount >= 100_000_000  { throw GRPCTimeoutError.tooManyDigits }

    // See "Timeout" in https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests
    let description = "\(amount) \(unit.rawValue)"
    let nanoseconds = Int64(amount) * Int64(unit.asNanoseconds)

    return GRPCTimeout(nanoseconds: nanoseconds, description: description)
  }

  /// Creates a new GRPCTimeout for the given amount of hours.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of hours this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of hours.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func hours(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(amount, .hours)
  }

  /// Creates a new GRPCTimeout for the given amount of minutes.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of minutes this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of minutes.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func minutes(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(amount, .minutes)
  }

  /// Creates a new GRPCTimeout for the given amount of seconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of seconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of seconds.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func seconds(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(amount, .seconds)
  }

  /// Creates a new GRPCTimeout for the given amount of milliseconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of milliseconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of milliseconds.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func milliseconds(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(amount, .milliseconds)
  }

  /// Creates a new GRPCTimeout for the given amount of microseconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of microseconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of microseconds.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func microseconds(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(amount, .microseconds)
  }

  /// Creates a new GRPCTimeout for the given amount of nanoseconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of nanoseconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of nanoseconds.
  /// - Throws: `GRPCTimeoutError` if the amount was negative or more than 8 digits long.
  public static func nanoseconds(_ amount: Int) throws -> GRPCTimeout {
    return try makeTimeout(amount, .nanoseconds)
  }
}

extension GRPCTimeout {
  /// Returns a NIO `TimeAmount` representing the amount of time as this timeout.
  public var asNIOTimeAmount: TimeAmount {
    return TimeAmount.nanoseconds(numericCast(nanoseconds))
  }
}

private enum GRPCTimeoutUnit: String {
  case hours = "H"
  case minutes = "M"
  case seconds = "S"
  case milliseconds = "m"
  case microseconds = "u"
  case nanoseconds = "n"

  internal var asNanoseconds: Int {
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
