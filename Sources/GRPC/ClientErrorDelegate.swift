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
import Foundation
import Logging

/// Delegate called when errors are caught by the client on individual HTTP/2 streams and errors in
/// the underlying HTTP/2 connection.
///
/// The intended use of this protocol is with `ClientConnection`. In order to avoid retain
/// cycles, classes implementing this delegate **must not** maintain a strong reference to the
/// `ClientConnection`.
public protocol ClientErrorDelegate: class {
  /// Called when the client catches an error.
  ///
  /// - Parameters:
  ///   - error: The error which was caught.
  ///   - file: The file where the error was raised.
  ///   - line: The line within the file where the error was raised.
  func didCatchError(_ error: Error, file: StaticString, line: Int)
}

/// A `ClientErrorDelegate` which logs errors only in debug builds.
public class DebugOnlyLoggingClientErrorDelegate: ClientErrorDelegate {
  public static let shared = DebugOnlyLoggingClientErrorDelegate()
  private let logger = Logger(labelSuffix: "ClientErrorDelegate")

  private init() { }

  public func didCatchError(_ error: Error, file: StaticString, line: Int) {
    debugOnly {
      self.logger.error(
        "client error",
        metadata: [MetadataKey.error: "\(error)"],
        file: "\(file)",
        function: "<unknown>",
        line: UInt(line)
      )
    }
  }
}

/// A utility function that runs the body code only in debug builds, without emitting compiler
/// warnings.
///
/// This is currently the only way to do this in Swift: see
/// https://forums.swift.org/t/support-debug-only-code/11037 for a discussion.
internal func debugOnly(_ body: () -> Void) {
  assert({ body(); return true }())
}
