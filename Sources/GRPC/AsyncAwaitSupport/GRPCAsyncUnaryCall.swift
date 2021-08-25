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
import Foundation
import Logging
import NIOCore
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import SwiftProtobuf

#if compiler(>=5.5)

/// A unary gRPC call. The request is sent on initialization.
///
/// Note: while this object is a `struct`, its implementation delegates to `Call`. It therefore
/// has reference semantics.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct GRPCAsyncUnaryCall<RequestPayload, ResponsePayload>: AsyncUnaryResponseClientCall {
  private let call: Call<RequestPayload, ResponsePayload>
  private let responseParts: UnaryResponseParts<ResponsePayload>

  /// The options used to make the RPC.
  public var options: CallOptions {
    self.call.options
  }

  /// Cancel this RPC if it hasn't already completed.
  public func cancel() async throws {
    try await self.call.cancel().get()
  }

  // MARK: - Response Parts

  /// The initial metadata returned from the server.
  public var initialMetadata: HPACKHeaders {
    // swiftformat:disable:next redundantGet
    get async throws {
      try await self.responseParts.initialMetadata.get()
    }
  }

  /// The response message returned from the service if the call is successful. This may be failed
  /// if the call encounters an error.
  ///
  /// Callers should rely on the `status` of the call for the canonical outcome.
  public var response: ResponsePayload {
    // swiftformat:disable:next redundantGet
    get async throws {
      try await self.responseParts.response.get()
    }
  }

  /// The trailing metadata returned from the server.
  public var trailingMetadata: HPACKHeaders {
    // swiftformat:disable:next redundantGet
    get async throws {
      try await self.responseParts.trailingMetadata.get()
    }
  }

  /// The final status of the the RPC.
  public var status: GRPCStatus {
    // swiftformat:disable:next redundantGet
    get async {
      // force-try because this future will _always_ be fulfilled with success.
      try! await self.responseParts.status.get()
    }
  }

  internal init(call: Call<RequestPayload, ResponsePayload>) {
    self.call = call
    self.responseParts = UnaryResponseParts(on: call.eventLoop)
  }

  internal func invoke(_ request: RequestPayload) {
    self.call.invokeUnaryRequest(
      request,
      onError: self.responseParts.handleError(_:),
      onResponsePart: self.responseParts.handle(_:)
    )
  }
}

#endif
