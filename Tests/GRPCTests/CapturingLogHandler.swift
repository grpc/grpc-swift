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
import struct Foundation.Date
import Logging
import NIOConcurrencyHelpers

/// A `LogHandler` factory which captures all logs emitted by the handlers it makes.
internal class CapturingLogHandlerFactory {
  private var lock = Lock()
  private var _logs: [CapturedLog] = []

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
      self.lock.withLockVoid {
        self._logs.append(log)
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

  fileprivate init(label: String, capture: @escaping (CapturedLog) -> ()) {
    self.label = label
    self.capture = capture
  }

  internal func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    file: String,
    function: String,
    line: UInt
  ) {
    let merged: Logger.Metadata

    if let metadata = metadata {
      merged = self.metadata.merging(metadata, uniquingKeysWith: { old, new in return new })
    } else {
      merged = self.metadata
    }

    let log = CapturedLog(
      label: self.label,
      level: level,
      message: message,
      metadata: merged,
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
