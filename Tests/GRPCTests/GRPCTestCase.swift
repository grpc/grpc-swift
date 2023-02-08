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
import GRPC
import Logging
import XCTest

/// This should be used instead of `XCTestCase`.
class GRPCTestCase: XCTestCase {
  /// Unless `GRPC_ALWAYS_LOG` is set, logs will only be printed if a test case fails.
  private static let alwaysLog = Bool(
    fromTruthLike: ProcessInfo.processInfo.environment["GRPC_ALWAYS_LOG"],
    defaultingTo: false
  )

  private static let runTimeSensitiveTests = Bool(
    fromTruthLike: ProcessInfo.processInfo.environment["ENABLE_TIMING_TESTS"],
    defaultingTo: true
  )

  override func setUp() {
    super.setUp()
    self.logFactory = CapturingLogHandlerFactory(printWhenCaptured: GRPCTestCase.alwaysLog)
  }

  override func tearDown() {
    // Only print logs when there's a failure and we're *not* always logging (when we are always
    // logging, logs will be printed as they're caught).
    if !GRPCTestCase.alwaysLog, (self.testRun.map { $0.totalFailureCount > 0 } ?? false) {
      let logs = self.capturedLogs()
      self.printCapturedLogs(logs)
    }

    super.tearDown()
  }

  func runTimeSensitiveTests() -> Bool {
    let shouldRun = GRPCTestCase.runTimeSensitiveTests
    if !shouldRun {
      print("Skipping '\(self.name)' as ENABLE_TIMING_TESTS=false")
    }
    return shouldRun
  }

  private(set) var logFactory: CapturingLogHandlerFactory!

  /// A general-use logger.
  var logger: Logger {
    return Logger(label: "grpc", factory: self.logFactory.make)
  }

  /// A logger for clients to use.
  var clientLogger: Logger {
    // Label is ignored; we already have a handler.
    return Logger(label: "client", factory: self.logFactory.make)
  }

  /// A logger for servers to use.
  var serverLogger: Logger {
    // Label is ignored; we already have a handler.
    return Logger(label: "server", factory: self.logFactory.make)
  }

  /// The default client call options using `self.clientLogger`.
  var callOptionsWithLogger: CallOptions {
    return CallOptions(logger: self.clientLogger)
  }

  /// Returns all captured logs sorted by date.
  private func capturedLogs() -> [CapturedLog] {
    assert(self.logFactory != nil, "Missing call to super.setUp()")

    var logs = self.logFactory.clearCapturedLogs()
    logs.sort(by: { $0.date < $1.date })

    return logs
  }

  /// Prints all captured logs.
  private func printCapturedLogs(_ logs: [CapturedLog]) {
    print("Test Case '\(self.name)' logs started")

    // The logs are already sorted by date.
    let formatter = CapturedLogFormatter()
    for log in logs {
      print(formatter.string(for: log))
    }

    print("Test Case '\(self.name)' logs finished")
  }
}

extension Bool {
  fileprivate init(fromTruthLike value: String?, defaultingTo defaultValue: Bool) {
    switch value?.lowercased() {
    case "0", "false", "no":
      self = false
    case "1", "true", "yes":
      self = true
    default:
      self = defaultValue
    }
  }
}
