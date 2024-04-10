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

/// Client resource usage stats.
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

  init() {
    self.time = Double(DispatchTime.now().uptimeNanoseconds) * 1e-9
    if let usage = System.resourceUsage() {
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

/// Server resource usage stats.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal struct ServerStats: Sendable {
  var time: Double
  var userTime: Double
  var systemTime: Double
  var totalCPUTime: UInt64
  var idleCPUTime: UInt64

  init(
    time: Double,
    userTime: Double,
    systemTime: Double,
    totalCPUTime: UInt64,
    idleCPUTime: UInt64
  ) {
    self.time = time
    self.userTime = userTime
    self.systemTime = systemTime
    self.totalCPUTime = totalCPUTime
    self.idleCPUTime = idleCPUTime
  }

  init() async throws {
    self.time = Double(DispatchTime.now().uptimeNanoseconds) * 1e-9
    if let usage = System.resourceUsage() {
      self.userTime = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) * 1e-6
      self.systemTime = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) * 1e-6
    } else {
      self.userTime = 0
      self.systemTime = 0
    }
    let (totalCPUTime, idleCPUTime) = try await ServerStats.getTotalAndIdleCPUTime()
    self.totalCPUTime = totalCPUTime
    self.idleCPUTime = idleCPUTime
  }

  internal func difference(to stats: ServerStats) -> ServerStats {
    return ServerStats(
      time: self.time - stats.time,
      userTime: self.userTime - stats.userTime,
      systemTime: self.systemTime - stats.systemTime,
      totalCPUTime: self.totalCPUTime - stats.totalCPUTime,
      idleCPUTime: self.idleCPUTime - stats.idleCPUTime
    )
  }

  /// Computes the total and idle CPU time after extracting stats from the first line of '/proc/stat'.
  ///
  /// The first line in '/proc/stat' file looks as follows:
  /// CPU [user] [nice] [system] [idle] [iowait] [irq] [softirq]
  /// The totalCPUTime is computed as follows:
  /// total = user + nice + system + idle
  private static func getTotalAndIdleCPUTime() async throws -> (
    totalCPUTime: UInt64, idleCPUTime: UInt64
  ) {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Linux) || os(Android)
    let contents: ByteBuffer
    do {
      contents = try await ByteBuffer(
        contentsOf: "/proc/stat",
        maximumSizeAllowed: .kilobytes(20)
      )
    } catch {
      return (0, 0)
    }

    let view = contents.readableBytesView
    guard let firstNewLineIndex = view.firstIndex(of: UInt8(ascii: "\n")) else {
      return (0, 0)
    }
    let firstLine = String(buffer: ByteBuffer(view[0 ... firstNewLineIndex]))

    let lineComponents = firstLine.components(separatedBy: " ")
    if lineComponents.count < 5 || lineComponents[0] != "CPU" {
      return (0, 0)
    }

    let CPUTime: [UInt64] = lineComponents[1 ... 4].compactMap { UInt64($0) }
    if CPUTime.count < 4 {
      return (0, 0)
    }

    let totalCPUTime = CPUTime.reduce(0, +)
    return (totalCPUTime, CPUTime[3])

    #else
    return (0, 0)
    #endif
  }
}

extension System {
  fileprivate static func resourceUsage() -> rusage? {
    var usage = rusage()

    if getrusage(OUR_RUSAGE_SELF, &usage) == 0 {
      return usage
    } else {
      return nil
    }
  }
}
