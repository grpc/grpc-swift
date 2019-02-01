import Foundation
import NIO

public enum GRPCTimeoutUnit: String {
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

public struct GRPCTimeout: CustomStringConvertible {
  public let description: String
  private let nanoseconds: Int64

  private init?(_ amount: Int, _ unit: GRPCTimeoutUnit) {
    // Timeouts must be positive and at most 8-digits.
    guard amount >= 0, amount < 100_000_000 else { return nil }

    self.description = "\(amount) \(unit.rawValue)"
    self.nanoseconds = Int64(amount) * Int64(unit.asNanoseconds)
  }

  public static func hours(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .hours)
  }

  public static func minutes(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .minutes)
  }

  public static func seconds(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .seconds)
  }

  public static func milliseconds(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .milliseconds)
  }

  public static func microseconds(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .microseconds)
  }

  public static func nanoseconds(_ amount: Int) -> GRPCTimeout? {
    return GRPCTimeout(amount, .nanoseconds)
  }
}

extension GRPCTimeout {
  public var asNIOTimeAmount: TimeAmount {
    return TimeAmount.nanoseconds(numericCast(nanoseconds))
  }
}
