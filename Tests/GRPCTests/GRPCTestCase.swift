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
import XCTest
import Logging

/// A test case which initializes the logging system once.
///
/// This should be used instead of `XCTestCase`.
class GRPCTestCase: XCTestCase {
  // Travis will fail the CI if there is too much logging, but it can be useful when running
  // locally; conditionally enable it based on the environment.
  //
  // https://docs.travis-ci.com/user/environment-variables/#default-environment-variables
  private static let isCI = Bool(
      fromTruthLike: ProcessInfo.processInfo.environment["CI"],
      defaultingTo: false
  )
  private static let isLoggingEnabled = !isCI

  private static let runTimeSensitiveTests = Bool(
      fromTruthLike: ProcessInfo.processInfo.environment["ENABLE_TIMING_TESTS"],
      defaultingTo: true
  )

  // `LoggingSystem.bootstrap` must be called once per process. This is the suggested approach to
  // workaround this for XCTestCase.
  //
  // See: https://github.com/apple/swift-log/issues/77
  private static let isLoggingConfigured: Bool = {
    LoggingSystem.bootstrap { label in
      guard isLoggingEnabled else {
        return BlackHole()
      }
      var handler = StreamLogHandler.standardOutput(label: label)
      handler.logLevel = .debug
      return handler
    }
    return true
  }()

  override class func setUp() {
    super.setUp()
    XCTAssertTrue(GRPCTestCase.isLoggingConfigured)
  }

  func runTimeSensitiveTests() -> Bool {
    let shouldRun = GRPCTestCase.runTimeSensitiveTests
    if !shouldRun {
      print("Skipping '\(self.name)' as ENABLE_TIMING_TESTS=false")
    }
    return shouldRun
  }
}

/// A `LogHandler` which does nothing with log messages.
struct BlackHole: LogHandler {
  func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
    ()
  }

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get {
      return metadata[key]
    }
    set(newValue) {
      self.metadata[key] = newValue
    }
  }

  var metadata: Logger.Metadata = [:]
  var logLevel: Logger.Level = .critical
}

fileprivate extension Bool {
  init(fromTruthLike value: String?, defaultingTo defaultValue: Bool) {
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
