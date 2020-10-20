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

import Foundation

/// Get the current time.
/// - returns: The current time.
func grpcTimeNow() -> DispatchTime {
  return DispatchTime.now()
}

extension DispatchTime {
  /// Subtraction between two DispatchTimes giving the result in Nanoseconds
  static func - (_ a: DispatchTime, _ b: DispatchTime) -> Nanoseconds {
    return Nanoseconds(value: a.uptimeNanoseconds - b.uptimeNanoseconds)
  }
}

/// A number of nanoseconds
struct Nanoseconds {
  /// The actual number of nanoseconds
  var value: UInt64
}

extension Nanoseconds {
  /// Convert to a potentially fractional number of seconds.
  func asSeconds() -> Double {
    return Double(self.value) * 1e-9
  }
}

extension Nanoseconds: CustomStringConvertible {
  /// Description to aid debugging.
  var description: String {
    return "\(self.value) ns"
  }
}
