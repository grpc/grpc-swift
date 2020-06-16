/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIO

/// A time limit for an RPC.
///
/// RPCs may have a time limit imposed on them by a caller which may be timeout or deadline based.
/// If the RPC has not completed before the limit is reached then the call will be cancelled and
/// completed with a `.deadlineExceeded` status code.
///
/// - Note: Servers may impose a time limit on an RPC independent of the client's time limit; RPCs
///   may therefore complete with `.deadlineExceeded` even if no time limit was set by the client.
public struct TimeLimit: Equatable, CustomStringConvertible {
  // private but for shimming.
  internal enum Wrapped: Equatable {
    case none
    case timeout(TimeAmount)
    case deadline(NIODeadline)
  }

  // private but for shimming.
  internal var wrapped: Wrapped

  private init(_ wrapped: Wrapped) {
    self.wrapped = wrapped
  }

  /// No time limit, the RPC will not be automatically cancelled by the client. Note: some services
  /// may impose a time limit on RPCs independent of the client's time limit.
  public static let none = TimeLimit(.none)

  /// Create a timeout before which the RPC must have completed. Failure to complete before the
  /// deadline will result in the RPC being cancelled.
  ///
  /// - Note: The timeout is started once the call has been invoked and the call may timeout waiting
  ///   for an active connection.
  public static func timeout(_ timeout: TimeAmount) -> TimeLimit {
    return TimeLimit(.timeout(timeout))
  }

  /// Create a point in time by which the RPC must have completed. Failure to complete before the
  /// deadline will result in the RPC being cancelled.
  public static func deadline(_ deadline: NIODeadline) -> TimeLimit {
    return TimeLimit(.deadline(deadline))
  }

  /// Return the timeout, if one was set.
  public var timeout: TimeAmount? {
    switch self.wrapped {
    case .timeout(let timeout):
      return timeout

    case .none, .deadline:
      return nil
    }
  }

  /// Return the deadline, if one was set.
  public var deadline: NIODeadline? {
    switch self.wrapped {
    case .deadline(let deadline):
      return deadline

    case .none, .timeout:
      return nil
    }

  }
}

extension TimeLimit {
  /// Make a non-distant-future deadline from the give time limit.
  internal func makeDeadline() -> NIODeadline {
    switch self.wrapped {
    case .none:
      return .distantFuture

    case .timeout(let timeout) where timeout.nanoseconds == .max:
      return .distantFuture

    case .timeout(let timeout):
      return .now() + timeout

    case .deadline(let deadline):
      return deadline
    }
  }

  public var description: String {
    switch self.wrapped {
    case .none:
      return "none"

    case .timeout(let timeout) where timeout.nanoseconds == .max:
      return "timeout=never"

    case .timeout(let timeout):
      return "timeout=\(timeout.nanoseconds) nanoseconds"

    case .deadline(let deadline) where deadline == .distantFuture:
      return "deadline=.distantFuture"

    case .deadline(let deadline):
      return "deadline=\(deadline.uptimeNanoseconds) uptimeNanoseconds"
    }
  }
}
