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
import NIO
import NIOHPACK

/// A container for RPC response parts.
internal struct ResponsePartContainer<Response: GRPCPayload> {
  /// The type of handler for response message part.
  enum ResponseHandler {
    case unary(EventLoopPromise<Response>)
    case stream((Response) -> Void)
  }

  /// A promise for the initial metadata.
  let initialMetadataPromise: EventLoopPromise<HPACKHeaders>

  /// A handler for response messages.
  let responseHandler: ResponseHandler

  /// A promise for the trailing metadata.
  let trailingMetadataPromise: EventLoopPromise<HPACKHeaders>

  /// A promise for the call status.
  let statusPromise: EventLoopPromise<GRPCStatus>

  var initialMetadata: EventLoopFuture<HPACKHeaders> {
    return self.initialMetadataPromise.futureResult
  }

  var trailingMetadata: EventLoopFuture<HPACKHeaders> {
    return self.trailingMetadataPromise.futureResult
  }

  var status: EventLoopFuture<GRPCStatus> {
    return self.statusPromise.futureResult
  }

  /// Fail all promises - except for the status promise - with the given error status. Succeed the
  /// status promise.
  func fail(with status: GRPCStatus) {
    self.initialMetadataPromise.fail(status)
    switch self.responseHandler {
    case .unary(let response):
      response.fail(status)
    case .stream:
      ()
    }
    self.trailingMetadataPromise.fail(status)
    // We always succeed the status.
    self.statusPromise.succeed(status)
  }

  /// Make a response container for a unary response.
  init(eventLoop: EventLoop, unaryResponsePromise: EventLoopPromise<Response>) {
    self.initialMetadataPromise = eventLoop.makePromise()
    self.trailingMetadataPromise = eventLoop.makePromise()
    self.statusPromise = eventLoop.makePromise()
    self.responseHandler = .unary(unaryResponsePromise)
  }

  /// Make a response container for a response which is streamed.
  init(eventLoop: EventLoop, streamingResponseHandler: @escaping (Response) -> Void) {
    self.initialMetadataPromise = eventLoop.makePromise()
    self.trailingMetadataPromise = eventLoop.makePromise()
    self.statusPromise = eventLoop.makePromise()
    self.responseHandler = .stream(streamingResponseHandler)
  }
}
