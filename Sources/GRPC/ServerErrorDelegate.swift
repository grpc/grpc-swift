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
import NIOHTTP1

public protocol ServerErrorDelegate: AnyObject {
  //! FIXME: Provide more context about where the error was thrown, i.e. using `GRPCError`.
  /// Called when an error is thrown in the channel pipeline.
  func observeLibraryError(_ error: Error)

  /// Transforms the given error (thrown somewhere inside the gRPC library) into a new error.
  ///
  /// This allows library users to transform errors which may be out of their control
  /// into more meaningful `GRPCStatus` errors before they are sent to the user.
  ///
  /// - note:
  /// Errors returned by this method are not passed to `observe` again.
  ///
  /// - note:
  /// This defaults to returning `nil`. In that case, if the original error conforms to `GRPCStatusTransformable`,
  /// that error's `asGRPCStatus()` result will be sent to the user. If that's not the case, either,
  /// `GRPCStatus.processingError` is returned.
  func transformLibraryError(_ error: Error) -> GRPCStatusAndMetadata?

  @available(
    *,
    deprecated,
    message: "Please use the new transformLibraryError that returns a GRPCStatusAndMetadata instead."
  )
  func transformLibraryError(_ error: Error) -> GRPCStatus?

  /// Called when a request's status or response promise is failed somewhere in the user-provided request handler code.
  /// - Parameters:
  ///   - error: The original error the status/response promise was failed with.
  ///   - request: The headers of the request whose status/response promise was failed.
  func observeRequestHandlerError(_ error: Error, request: HTTPRequestHead)

  /// Transforms the given status or response promise failure into a new error.
  ///
  /// This allows library users to transform errors which happen during their handling of the request
  /// into more meaningful `GRPCStatus` errors before they are sent to the user.
  ///
  /// - note:
  /// Errors returned by this method are not passed to `observe` again.
  ///
  /// - note:
  /// This defaults to returning `nil`. In that case, if the original error conforms to `GRPCStatusTransformable`,
  /// that error's `asGRPCStatus()` result will be sent to the user. If that's not the case, either,
  /// `GRPCStatus.processingError` is returned.
  ///
  /// - Parameters:
  ///   - error: The original error the status/response promise was failed with.
  ///   - request: The headers of the request whose status/response promise was failed.
  func transformRequestHandlerError(_ error: Error, request: HTTPRequestHead)
    -> GRPCStatusAndMetadata?

  @available(
    *,
    deprecated,
    message: "Please use the new transformLibraryError that returns a GRPCStatusAndMetadata instead."
  )
  func transformRequestHandlerError(_ error: Error, request: HTTPRequestHead) -> GRPCStatus?
}

public extension ServerErrorDelegate {
  func observeLibraryError(_ error: Error) {}
  func transformLibraryError(_ error: Error) -> GRPCStatusAndMetadata? { return nil }
  func transformLibraryError(_ error: Error) -> GRPCStatus? { return nil }

  func observeRequestHandlerError(_ error: Error, request: HTTPRequestHead) {}
  func transformRequestHandlerError(
    _ error: Error,
    request: HTTPRequestHead
  ) -> GRPCStatusAndMetadata? { return nil }
  func transformRequestHandlerError(_ error: Error,
                                    request: HTTPRequestHead) -> GRPCStatus? { return nil }
}
