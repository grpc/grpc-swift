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

import Logging
import NIOConcurrencyHelpers

import struct Foundation.Date
import class Foundation.DateFormatter

/// A `LogHandler` factory which captures all logs emitted by the handlers it makes.
internal class CapturingLogHandlerFactory {
  private var lock = NIOLock()
  private var _logs: [CapturedLog] = []

  private var logFormatter: CapturedLogFormatter?

  init(printWhenCaptured: Bool) {
    if printWhenCaptured {
      self.logFormatter = CapturedLogFormatter()
    } else {
      self.logFormatter = nil
    }
  }

  /// Returns all captured logs and empties the store of captured logs.
  func clearCapturedLogs() -> [CapturedLog] {
    return self.lock.withLock {
      let logs = self._logs
      self._logs.removeAll()
      return logs
    }
  }

  /// Make a `LogHandler` whose logs will be recorded by this factory.
  func make(_ label: String) -> LogHandler {
    return CapturingLogHandler(label: label) { log in
      self.lock.withLock {
        self._logs.append(log)
      }

      // If we have a formatter, print the log as well.
      if let formatter = self.logFormatter {
        print(formatter.string(for: log))
      }
    }
  }
}

/// A captured log.
internal struct CapturedLog {
  var label: String
  var level: Logger.Level
  var message: Logger.Message
  var metadata: Logger.Metadata
  var source: String
  var file: String
  var function: String
  var line: UInt
  var date: Date
}

/// A log handler which captures all logs it records.
internal struct CapturingLogHandler: LogHandler {
  private let capture: (CapturedLog) -> Void

  internal let label: String
  internal var metadata: Logger.Metadata = [:]
  internal var logLevel: Logger.Level = .trace

  fileprivate init(label: String, capture: @escaping (CapturedLog) -> Void) {
    self.label = label
    self.capture = capture
  }

  internal func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    let merged: Logger.Metadata

    if let metadata = metadata {
      merged = self.metadata.merging(metadata, uniquingKeysWith: { _, new in new })
    } else {
      merged = self.metadata
    }

    let log = CapturedLog(
      label: self.label,
      level: level,
      message: message,
      metadata: merged,
      source: source,
      file: file,
      function: function,
      line: line,
      date: Date()
    )

    self.capture(log)
  }

  internal subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get {
      return self.metadata[metadataKey]
    }
    set {
      self.metadata[metadataKey] = newValue
    }
  }
}

struct CapturedLogFormatter {
  private var dateFormatter: DateFormatter

  init() {
    self.dateFormatter = DateFormatter()
    // We don't care about the date.
    self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
  }

  func string(for log: CapturedLog) -> String {
    let date = self.dateFormatter.string(from: log.date)
    let level = log.level.short

    // Format the metadata.
    let formattedMetadata = log.metadata
      .sorted(by: { $0.key < $1.key })
      .map { key, value in "\(key)=\(value)" }
      .joined(separator: " ")

    return "\(date) \(level) \(log.label): \(log.message) { \(formattedMetadata) }"
  }
}

extension Logger.Level {
  fileprivate var short: String {
    switch self {
    case .info:
      return "I"
    case .debug:
      return "D"
    case .warning:
      return "W"
    case .error:
      return "E"
    case .critical:
      return "C"
    case .trace:
      return "T"
    case .notice:
      return "N"
    }
  }
}
