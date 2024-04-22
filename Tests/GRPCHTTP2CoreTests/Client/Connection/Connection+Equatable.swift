/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

import GRPCCore

@testable import GRPCHTTP2Core

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension Connection.Event: Equatable {
  public static func == (lhs: Connection.Event, rhs: Connection.Event) -> Bool {
    switch (lhs, rhs) {
    case (.connectSucceeded, .connectSucceeded),
      (.connectFailed, .connectFailed):
      return true

    case (.goingAway(let lhsCode, let lhsReason), .goingAway(let rhsCode, let rhsReason)):
      return lhsCode == rhsCode && lhsReason == rhsReason

    case (.closed(let lhsReason), .closed(let rhsReason)):
      return lhsReason == rhsReason

    default:
      return false
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension Connection.CloseReason: Equatable {
  public static func == (lhs: Connection.CloseReason, rhs: Connection.CloseReason) -> Bool {
    switch (lhs, rhs) {
    case (.idleTimeout, .idleTimeout),
      (.keepaliveTimeout, .keepaliveTimeout),
      (.initiatedLocally, .initiatedLocally),
      (.remote, .remote):
      return true

    case (.error(let lhsError), .error(let rhsError)):
      if let lhs = lhsError as? RPCError, let rhs = rhsError as? RPCError {
        return lhs == rhs
      } else {
        return true
      }

    default:
      return false
    }
  }
}
