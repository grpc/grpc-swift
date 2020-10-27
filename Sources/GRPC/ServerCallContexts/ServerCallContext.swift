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
import NIO
import NIOHPACK
import NIOHTTP1
import SwiftProtobuf

/// Protocol declaring a minimum set of properties exposed by *all* types of call contexts.
public protocol ServerCallContext: AnyObject {
  /// The event loop this call is served on.
  var eventLoop: EventLoop { get }

  /// Request headers for this request.
  var headers: HPACKHeaders { get }

  /// The logger used for this call.
  var logger: Logger { get }

  /// Whether compression should be enabled for responses, defaulting to `true`. Note that for
  /// this value to take effect compression must have been enabled on the server and a compression
  /// algorithm must have been negotiated with the client.
  var compressionEnabled: Bool { get set }
}

/// Base class providing data provided to the framework user for all server calls.
open class ServerCallContextBase: ServerCallContext {
  public let eventLoop: EventLoop
  public let headers: HPACKHeaders
  public let logger: Logger
  public var compressionEnabled: Bool = true

  /// Metadata to return at the end of the RPC. If this is required it should be updated before
  /// the `responsePromise` or `statusPromise` is fulfilled.
  public var trailers = HPACKHeaders()

  public init(eventLoop: EventLoop, headers: HPACKHeaders, logger: Logger) {
    self.eventLoop = eventLoop
    self.headers = headers
    self.logger = logger
  }

  @available(*, deprecated, renamed: "init(eventLoop:headers:logger:)")
  public init(eventLoop: EventLoop, request: HTTPRequestHead, logger: Logger) {
    self.eventLoop = eventLoop
    self.headers = HPACKHeaders(httpHeaders: request.headers, normalizeHTTPHeaders: false)
    self.logger = logger
  }

  /// Processes an error, transforming it into a 'GRPCStatus' and any trailers to send to the peer.
  internal func processError(
    _ error: Error,
    delegate: ServerErrorDelegate?
  ) -> (GRPCStatus, HPACKHeaders) {
    // Observe the error if we have a delegate.
    delegate?.observeRequestHandlerError(error, headers: self.headers)

    // What status are we terminating this RPC with?
    // - If we have a delegate, try transforming the error. If the delegate returns trailers, merge
    //   them with any on the call context.
    // - If we don't have a delegate, then try to transform the error to a status.
    // - Fallback to a generic error.
    let status: GRPCStatus
    let trailers: HPACKHeaders

    if let transformed = delegate?.transformRequestHandlerError(error, headers: self.headers) {
      status = transformed.status
      if var transformedTrailers = transformed.trailers {
        // The delegate returned trailers: merge in those from the context as well.
        transformedTrailers.add(contentsOf: self.trailers)
        trailers = transformedTrailers
      } else {
        trailers = self.trailers
      }
    } else if let grpcStatusTransformable = error as? GRPCStatusTransformable {
      status = grpcStatusTransformable.makeGRPCStatus()
      trailers = self.trailers
    } else {
      // Eh... well, we don't what status to use. Use a generic one.
      status = .processingError
      trailers = self.trailers
    }

    return (status, trailers)
  }
}
