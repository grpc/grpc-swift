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
import NIOCore
import NIOFileSystem

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Darwin
#elseif os(Linux) || os(FreeBSD) || os(Android)
import Glibc
#else
let badOS = { fatalError("unsupported OS") }()
#endif

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
private let OUR_RUSAGE_SELF: Int32 = RUSAGE_SELF
#elseif os(Linux) || os(FreeBSD) || os(Android)
private let OUR_RUSAGE_SELF: Int32 = RUSAGE_SELF.rawValue
#endif

/// Current server stats.
internal struct ServerStats: Sendable {
  let time: Double
  let userTime: Double
  let systemTime: Double
  let totalCpuTime: UInt64
  let idleCpuTime: UInt64

  init(
    time: Double,
    userTime: Double,
    systemTime: Double,
    totalCpuTime: UInt64,
    idleCPuTime: UInt64
  ) {
    self.time = time
    self.userTime = userTime
    self.systemTime = systemTime
    self.totalCpuTime = totalCpuTime
    self.idleCpuTime = idleCPuTime
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
    if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
      let (totalCpuTime, idleCpuTime) = try await getTotalAndIdleCpuTime()
      self.totalCpuTime = totalCpuTime
      self.idleCpuTime = idleCpuTime
    } else {
      self.idleCpuTime = 0
      self.totalCpuTime = 0
    }
  }
}

internal func changeInStats(initialStats: ServerStats, currentStats: ServerStats) -> ServerStats {
  return ServerStats(
    time: currentStats.time - initialStats.time,
    userTime: currentStats.userTime - initialStats.userTime,
    systemTime: currentStats.systemTime - initialStats.systemTime,
    totalCpuTime: currentStats.totalCpuTime - initialStats.totalCpuTime,
    idleCPuTime: currentStats.idleCpuTime - initialStats.idleCpuTime
  )
}

/// Computes the total and idle CPU time after extracting stats from the first line of '/proc/stat'.
///
/// The first line in '/proc/stat' file looks as follows:
/// cpu [user] [nice] [system] [idle] [iowait] [irq] [softirq]
/// The totalCpuTime is computed as follows:
/// total = user + nice + system + idle
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private func getTotalAndIdleCpuTime() async throws -> (UInt64, UInt64) {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
  do {
    let contents = try await ByteBuffer(
      contentsOf: "/proc/stat",
      maximumSizeAllowed: .kilobytes(20)
    )

    guard let index = contents.readableBytesView.firstIndex(where: { $0 == UInt8("\n") }) else {
      return (0, 0)
    }

    guard let firstLine = contents.getString(at: 0, length: index) else {
      return (0, 0)
    }

    let lineComponents = firstLine.components(separatedBy: " ")
    if lineComponents.count < 5 || lineComponents[0] != "cpu" {
      return (0, 0)
    }

    let cpuTime: [UInt64] = lineComponents[1 ... 4].compactMap { UInt64($0) }
    if cpuTime.count < 4 {
      return (0, 0)
    }

    let totalCpuTime = cpuTime.reduce(0, +)
    return (totalCpuTime, cpuTime[3])
  } catch {
    return (0, 0)
  }
  #else
  return (0, 0)
  #endif
}
