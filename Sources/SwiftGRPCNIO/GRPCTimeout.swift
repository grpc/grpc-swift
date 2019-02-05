import Foundation
import NIO

/// A timeout for a gRPC call.
///
/// Timeouts must be positive and at most 8-digits long.
public struct GRPCTimeout: CustomStringConvertible {
  /// A description of the timeout in the format described in the
  /// [gRPC protocol](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md).
  public let description: String

  private let nanoseconds: Int64

  /// Creates a new GRPCTimeout with the given `amount` of the `unit`.
  ///
  /// `amount` must be positive and at most 8-digits.
  private init?(_ amount: Int, _ unit: GRPCTimeoutUnit) {
    // Timeouts must be positive and at most 8-digits.
    guard amount >= 0, amount < 100_000_000 else { return nil }

    self.description = "\(amount) \(unit.rawValue)"
    self.nanoseconds = Int64(amount) * Int64(unit.asNanoseconds)
  }

  /// Creates a new GRPCTimeout for the given amount of hours.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of hours this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of hours if the amount was valid, `nil` otherwise.
  public static func hours(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .hours)
  }

  /// Creates a new GRPCTimeout for the given amount of minutes.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of minutes this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of minutes if the amount was valid, `nil` otherwise.
  public static func minutes(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .minutes)
  }

  /// Creates a new GRPCTimeout for the given amount of seconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of seconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of seconds if the amount was valid, `nil` otherwise.
  public static func seconds(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .seconds)
  }

  /// Creates a new GRPCTimeout for the given amount of milliseconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of milliseconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of milliseconds if the amount was valid, `nil` otherwise.
  public static func milliseconds(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .milliseconds)
  }

  /// Creates a new GRPCTimeout for the given amount of microseconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of microseconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of microseconds if the amount was valid, `nil` otherwise.
  public static func microseconds(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .microseconds)
  }

  /// Creates a new GRPCTimeout for the given amount of nanoseconds.
  ///
  /// `amount` must be positive and at most 8-digits.
  ///
  /// - Parameter amount: the amount of nanoseconds this `GRPCTimeout` represents.
  /// - Returns: A `GRPCTimeout` representing the given number of nanoseconds if the amount was valid, `nil` otherwise.
  public static func nanoseconds(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .nanoseconds)
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
