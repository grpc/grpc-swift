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
import NIO

public protocol ServerErrorDelegate: class {
  //! FIXME: Provide more context about where the error was thrown.
  /// Called when an error is thrown in the channel pipeline.
  func observe(_ error: Error)

  /// Transforms the given error into a new error.
  ///
  /// This allows framework users to transform errors which may be out of their control
  /// due to third-party libraries, for example, into more meaningful errors or
  /// `GRPCStatus` errors. Errors returned from this protocol are not passed to
  /// `observe`.
  ///
  /// - note:
  /// This defaults to returning the provided error.
  func transform(_ error: Error) -> Error
}

public extension ServerErrorDelegate {
  func transform(_ error: Error) -> Error {
    return error
  }
}
