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
#if compiler(>=5.6)

import NIOHPACK

/// Async-await variant of BidirectionalStreamingCall.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncBidirectionalStreamingCall<Request: Sendable, Response: Sendable>: Sendable {
  private let call: Call<Request, Response>
  private let responseParts: StreamingResponseParts<Response>
  private let responseSource: PassthroughMessageSource<Response, Error>

  /// A request stream writer for sending messages to the server.
  public let requestStream: GRPCAsyncRequestStreamWriter<Request>

  /// The stream of responses from the server.
  public let responseStream: GRPCAsyncResponseStream<Response>

  /// The options used to make the RPC.
  public var options: CallOptions {
    return self.call.options
  }

  /// Cancel this RPC if it hasn't already completed.
  public func cancel() async throws {
    try await self.call.cancel().get()
  }

  // MARK: - Response Parts

  /// The initial metadata returned from the server.
  ///
  /// - Important: The initial metadata will only be available when the first response has been
  /// received. However, it is not necessary for the response to have been consumed before reading
  /// this property.
  public var initialMetadata: HPACKHeaders {
    get async throws {
      try await self.responseParts.initialMetadata.get()
    }
  }

  /// The trailing metadata returned from the server.
  ///
  /// - Important: Awaiting this property will suspend until the responses have been consumed.
  public var trailingMetadata: HPACKHeaders {
    get async throws {
      try await self.responseParts.trailingMetadata.get()
    }
  }

  /// The final status of the the RPC.
  ///
  /// - Important: Awaiting this property will suspend until the responses have been consumed.
  public var status: GRPCStatus {
    get async {
      // force-try acceptable because any error is encapsulated in a successful GRPCStatus future.
      try! await self.responseParts.status.get()
    }
  }

  private init(call: Call<Request, Response>) {
    self.call = call
    self.responseParts = StreamingResponseParts(on: call.eventLoop) { _ in }
    self.responseSource = PassthroughMessageSource<Response, Error>()
    self.responseStream = .init(PassthroughMessageSequence(consuming: self.responseSource))
    self.requestStream = call.makeRequestStreamWriter()
  }

  /// We expose this as the only non-private initializer so that the caller
  /// knows that invocation is part of initialisation.
  internal static func makeAndInvoke(call: Call<Request, Response>) -> Self {
    let asyncCall = Self(call: call)

    asyncCall.call.invokeStreamingRequests(
      onError: { error in
        asyncCall.responseParts.handleError(error)
        asyncCall.responseSource.finish(throwing: error)
        asyncCall.requestStream.asyncWriter.cancelAsynchronously()
      },
      onResponsePart: AsyncCall.makeResponsePartHandler(
        responseParts: asyncCall.responseParts,
        responseSource: asyncCall.responseSource,
        requestStream: asyncCall.requestStream
      )
    )

    return asyncCall
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal enum AsyncCall {
  internal static func makeResponsePartHandler<Response, Request>(
    responseParts: StreamingResponseParts<Response>,
    responseSource: PassthroughMessageSource<Response, Error>,
    requestStream: GRPCAsyncRequestStreamWriter<Request>?,
    requestType: Request.Type = Request.self
  ) -> (GRPCClientResponsePart<Response>) -> Void {
    return { responsePart in
      // Handle the metadata, trailers and status.
      responseParts.handle(responsePart)

      // Handle the response messages and status.
      switch responsePart {
      case .metadata:
        ()

      case let .message(response):
        // TODO: when we support backpressure we will need to stop ignoring the return value.
        _ = responseSource.yield(response)

      case let .end(status, _):
        if status.isOk {
          responseSource.finish()
        } else {
          responseSource.finish(throwing: status)
        }

        requestStream?.asyncWriter.cancelAsynchronously()
      }
    }
  }

  internal static func makeResponsePartHandler<Response, Request>(
    responseParts: UnaryResponseParts<Response>,
    requestStream: GRPCAsyncRequestStreamWriter<Request>?,
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> (GRPCClientResponsePart<Response>) -> Void {
    return { responsePart in
      // Handle (most of) all parts.
      responseParts.handle(responsePart)

      // Handle the status.
      switch responsePart {
      case .metadata, .message:
        ()
      case .end:
        requestStream?.asyncWriter.cancelAsynchronously()
      }
    }
  }
}

#endif
