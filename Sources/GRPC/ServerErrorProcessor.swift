/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import NIOHPACK

@usableFromInline
internal enum ServerErrorProcessor {
  /// Processes a library error to form a `GRPCStatus` and trailers to send back to the client.
  /// - Parameter error: The error to process.
  /// - Returns: The status and trailers to send to the client.
  @usableFromInline
  internal static func processLibraryError(
    _ error: Error,
    delegate: ServerErrorDelegate?
  ) -> (GRPCStatus, HPACKHeaders) {
    // Observe the error if we have a delegate.
    delegate?.observeLibraryError(error)

    // What status are we terminating this RPC with?
    // - If we have a delegate, try transforming the error. If the delegate returns trailers, merge
    //   them with any on the call context.
    // - If we don't have a delegate, then try to transform the error to a status.
    // - Fallback to a generic error.
    let status: GRPCStatus
    let trailers: HPACKHeaders

    if let transformed = delegate?.transformLibraryError(error) {
      status = transformed.status
      trailers = transformed.trailers ?? [:]
    } else if let grpcStatusTransformable = error as? GRPCStatusTransformable {
      status = grpcStatusTransformable.makeGRPCStatus()
      trailers = [:]
    } else {
      // Eh... well, we don't know what status to use. Use a generic one.
      status = .processingError(cause: error)
      trailers = [:]
    }

    return (status, trailers)
  }

  /// Processes an error, transforming it into a 'GRPCStatus' and any trailers to send to the peer.
  @usableFromInline
  internal static func processObserverError(
    _ error: Error,
    headers: HPACKHeaders,
    trailers: HPACKHeaders,
    delegate: ServerErrorDelegate?
  ) -> (GRPCStatus, HPACKHeaders) {
    // Observe the error if we have a delegate.
    delegate?.observeRequestHandlerError(error, headers: headers)

    // What status are we terminating this RPC with?
    // - If we have a delegate, try transforming the error. If the delegate returns trailers, merge
    //   them with any on the call context.
    // - If we don't have a delegate, then try to transform the error to a status.
    // - Fallback to a generic error.
    let status: GRPCStatus
    let mergedTrailers: HPACKHeaders

    if let transformed = delegate?.transformRequestHandlerError(error, headers: headers) {
      status = transformed.status
      if var transformedTrailers = transformed.trailers {
        // The delegate returned trailers: merge in those from the context as well.
        transformedTrailers.add(contentsOf: trailers)
        mergedTrailers = transformedTrailers
      } else {
        mergedTrailers = trailers
      }
    } else if let grpcStatusTransformable = error as? GRPCStatusTransformable {
      status = grpcStatusTransformable.makeGRPCStatus()
      mergedTrailers = trailers
    } else {
      // Eh... well, we don't what status to use. Use a generic one.
      status = .processingError(cause: error)
      mergedTrailers = trailers
    }

    return (status, mergedTrailers)
  }
}
