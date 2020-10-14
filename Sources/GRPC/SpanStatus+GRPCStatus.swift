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
import Tracing

extension SpanStatus {
  /// Initialize a `SpanStatus` by mapping the given `GRPCStatus`.
  /// - Parameter status: The `GRPCStatus` to map to a `SpanStatus`.
  init(_ status: GRPCStatus) {
    let canonicalCode: SpanStatus.CanonicalCode

    switch status.code {
    case .ok:
      canonicalCode = .ok
    case .cancelled:
      canonicalCode = .cancelled
    case .unknown:
      canonicalCode = .unknown
    case .invalidArgument:
      canonicalCode = .invalidArgument
    case .deadlineExceeded:
      canonicalCode = .deadlineExceeded
    case .notFound:
      canonicalCode = .notFound
    case .alreadyExists:
      canonicalCode = .alreadyExists
    case .permissionDenied:
      canonicalCode = .permissionDenied
    case .resourceExhausted:
      canonicalCode = .resourceExhausted
    case .failedPrecondition:
      canonicalCode = .failedPrecondition
    case .aborted:
      canonicalCode = .aborted
    case .outOfRange:
      canonicalCode = .outOfRange
    case .unimplemented:
      canonicalCode = .unimplemented
    case .internalError:
      canonicalCode = .internal
    case .unavailable:
      canonicalCode = .unavailable
    case .dataLoss:
      canonicalCode = .dataLoss
    case .unauthenticated:
      canonicalCode = .unauthenticated
    default:
      canonicalCode = .unknown
    }

    self = SpanStatus(canonicalCode: canonicalCode, message: status.message)
  }
}
