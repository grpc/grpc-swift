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
public protocol ClientErrorDelegate: AnyObject, GRPCPreconcurrencySendable {
  /// Called when the client catches an error.
  ///
  /// - Parameters:
  ///   - error: The error which was caught.
  ///   - logger: A logger with relevant metadata for the RPC or connection the error relates to.
  ///   - file: The file where the error was raised.
  ///   - line: The line within the file where the error was raised.
  func didCatchError(_ error: Error, logger: Logger, file: StaticString, line: Int)
}

extension ClientErrorDelegate {
  /// Calls `didCatchError(_:logger:file:line:)` with appropriate context placeholders when no
  /// context is available.
  internal func didCatchErrorWithoutContext(_ error: Error, logger: Logger) {
    self.didCatchError(error, logger: logger, file: "<unknown>", line: 0)
  }
}

/// A `ClientErrorDelegate` which logs errors.
public final class LoggingClientErrorDelegate: ClientErrorDelegate {
  /// A shared instance of this class.
  public static let shared = LoggingClientErrorDelegate()

  public init() {}

  public func didCatchError(_ error: Error, logger: Logger, file: StaticString, line: Int) {
    logger.error(
      "grpc client error",
      metadata: [MetadataKey.error: "\(error)"],
      source: "GRPC",
      file: "\(file)",
      function: "<unknown>",
      line: UInt(line)
    )
  }
}
