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

/// Async-await variant of `ClientStreamingCall`.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncClientStreamingCall<Request: Sendable, Response: Sendable>: Sendable {
  private let call: Call<Request, Response>
  private let responseParts: UnaryResponseParts<Response>

  /// A request stream writer for sending messages to the server.
  public let requestStream: GRPCAsyncRequestStreamWriter<Request>

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
  /// - Important: The initial metadata will only be available when the response has been received.
  public var initialMetadata: HPACKHeaders {
    get async throws {
      try await self.responseParts.initialMetadata.get()
    }
  }

  /// The response returned by the server.
  public var response: Response {
    get async throws {
      try await self.responseParts.response.get()
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
    self.responseParts = UnaryResponseParts(on: call.eventLoop)
    self.call.invokeStreamingRequests(
      onError: self.responseParts.handleError(_:),
      onResponsePart: self.responseParts.handle(_:)
    )
    self.requestStream = call.makeRequestStreamWriter()
  }

  /// We expose this as the only non-private initializer so that the caller
  /// knows that invocation is part of initialisation.
  internal static func makeAndInvoke(call: Call<Request, Response>) -> Self {
    Self(call: call)
  }
}

#endif
