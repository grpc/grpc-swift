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

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Darwin
#elseif os(Linux) || os(FreeBSD) || os(Android)
import Glibc
#else
let badOS = { fatalError("unsupported OS") }()
#endif

import Foundation

extension TimeInterval {
  init(_ value: timeval) {
    self.init(Double(value.tv_sec) + Double(value.tv_usec) * 1e-9)
  }
}

/// Holder for CPU time consumed.
struct CPUTime {
  /// Amount of user process time consumed.
  var userTime: TimeInterval
  /// Amount of system time consumed.
  var systemTime: TimeInterval
}

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
fileprivate let OUR_RUSAGE_SELF: Int32 = RUSAGE_SELF
#elseif os(Linux) || os(FreeBSD) || os(Android)
fileprivate let OUR_RUSAGE_SELF: Int32 = RUSAGE_SELF.rawValue
#endif

/// Get resource usage for this process.
/// - returns: The amount of CPU resource consumed.
func getResourceUsage() -> CPUTime {
  var usage = rusage()
  if getrusage(OUR_RUSAGE_SELF, &usage) == 0 {
    return CPUTime(
      userTime: TimeInterval(usage.ru_utime),
      systemTime: TimeInterval(usage.ru_stime)
    )
  } else {
    return CPUTime(userTime: 0, systemTime: 0)
  }
}
