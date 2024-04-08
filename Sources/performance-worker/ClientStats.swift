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

import Dispatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#else
let badOS = { fatalError("unsupported OS") }()
#endif

#if canImport(Darwin)
private let OUR_RUSAGE_SELF: Int32 = RUSAGE_SELF
#elseif canImport(Musl) || canImport(Glibc)
private let OUR_RUSAGE_SELF: Int32 = RUSAGE_SELF.rawValue
#endif

/// Usage stats.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal struct ClientStats: Sendable {
  var time: Double
  var userTime: Double
  var systemTime: Double

  init(
    time: Double,
    userTime: Double,
    systemTime: Double
  ) {
    self.time = time
    self.userTime = userTime
    self.systemTime = systemTime
  }

  init() async throws {
    self.time = Double(DispatchTime.now().uptimeNanoseconds) * 1e-9
    var usage = rusage()
    if getrusage(OUR_RUSAGE_SELF, &usage) == 0 {
      // Adding the seconds with the microseconds transformed into seconds to get the
      // real number of seconds as a `Double`.
      self.userTime = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) * 1e-6
      self.systemTime = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) * 1e-6
    } else {
      self.userTime = 0
      self.systemTime = 0
    }
  }

  internal func difference(to state: ClientStats) -> ClientStats {
    return ClientStats(
      time: self.time - state.time,
      userTime: self.userTime - state.userTime,
      systemTime: self.systemTime - state.systemTime
    )
  }
}
