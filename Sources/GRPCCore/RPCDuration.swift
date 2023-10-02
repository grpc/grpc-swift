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

/// A representation of a period of time with nanosecond precision.
///
/// The largest representable duration is `Int64.max` nanoseconds.
public struct RPCDuration: Sendable, Hashable {
  /// The number of nanoseconds in the duration.
  public var nanoseconds: Int64

  /// Creates a `RPCTimeout`.
  private init(amount: some BinaryInteger, unit: Unit) {
    // If we overflow at this point, which is certainly possible if `amount` is sufficiently large
    // and `unit` is `.hours`, clamp the nanosecond timeout to `Int64.max`. It's about 292 years so
    // it should be long enough for the user not to notice the difference should the rpc time out.
    let value = Int64(clamping: amount)
    let (partial, overflow) = value.multipliedReportingOverflow(by: unit.nanosecondsPerUnit)
    if overflow {
      self.nanoseconds = value.signum() < 0 ? .min : .max
    } else {
      self.nanoseconds = partial
    }
  }

  /// Creates a duration from given number of nanoseconds as a `BinaryInteger`.
  ///
  /// The duration will be clamped to `Int64.max` nanoseconds.
  ///
  /// - Parameter value: The number of nanoseconds.
  /// - Returns: A duration.
  public static func nanoseconds(_ value: some BinaryInteger) -> Self {
    return Self(amount: value, unit: .nanoseconds)
  }

  /// Creates a duration from given number of microseconds as a `BinaryInteger`.
  ///
  /// The duration will be clamped to `Int64.max` nanoseconds.
  ///
  /// - Parameter value: The number of microseconds.
  /// - Returns: A duration.
  public static func microseconds(_ value: some BinaryInteger) -> Self {
    return Self(amount: value, unit: .microseconds)
  }

  /// Creates a duration from given number of milliseconds as a `BinaryInteger`.
  ///
  /// The duration will be clamped to `Int64.max` nanoseconds.
  ///
  /// - Parameter value: The number of milliseconds.
  /// - Returns: A duration.
  public static func milliseconds(_ value: some BinaryInteger) -> Self {
    return Self(amount: value, unit: .milliseconds)
  }

  /// Creates a duration from given number of seconds as a `BinaryInteger`.
  ///
  /// The duration will be clamped to `Int64.max` nanoseconds.
  ///
  /// - Parameter value: The number of seconds.
  /// - Returns: A duration.
  public static func seconds(_ value: some BinaryInteger) -> Self {
    return Self(amount: value, unit: .seconds)
  }

  /// Creates a duration from given number of minutes as a `BinaryInteger`.
  ///
  /// The duration will be clamped to `Int64.max` nanoseconds.
  ///
  /// - Parameter value: The number of minutes.
  /// - Returns: A duration.
  public static func minutes(_ value: some BinaryInteger) -> Self {
    return Self(amount: value, unit: .minutes)
  }

  /// Creates a duration from given number of hours as a `BinaryInteger`.
  ///
  /// The duration will be clamped to `Int64.max` nanoseconds.
  ///
  /// - Parameter value: The number of hours.
  /// - Returns: A duration.
  public static func hours(_ value: some BinaryInteger) -> Self {
    return Self(amount: value, unit: .hours)
  }
}

extension RPCDuration {
  private enum Unit {
    case hours
    case minutes
    case seconds
    case milliseconds
    case microseconds
    case nanoseconds

    var nanosecondsPerUnit: Int64 {
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
}

extension RPCDuration {
  /// Creates an ``RPCDuration`` from the given `Duration`.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public init(_ duration: Duration) {
    let nanoseconds = duration.components.seconds * 1_000_000_000
    let (partial, _) = nanoseconds.addingReportingOverflow(
      duration.components.attoseconds / 1_000_000_000
    )
    self = .nanoseconds(partial)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Duration {
  /// Creates a `Duration` from the given ``RPCDuration``.
  public init(_ duration: RPCDuration) {
    let (secs, nanos) = duration.nanoseconds.quotientAndRemainder(dividingBy: 1_000_000_000)
    let attos = nanos * 1_000_000_000
    self = .init(secondsComponent: secs, attosecondsComponent: attos)
  }
}
