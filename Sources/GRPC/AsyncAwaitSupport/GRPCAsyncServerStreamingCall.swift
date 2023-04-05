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

import NIOCore
import NIOHPACK

/// Async-await variant of ``ServerStreamingCall``.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncServerStreamingCall<Request: Sendable, Response: Sendable> {
  private let call: Call<Request, Response>
  private let responseParts: StreamingResponseParts<Response>
  private let responseSource: NIOThrowingAsyncSequenceProducer<
    Response,
    Error,
    NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
    GRPCAsyncSequenceProducerDelegate
  >.Source

  /// The stream of responses from the server.
  public let responseStream: GRPCAsyncResponseStream<Response>

  /// The options used to make the RPC.
  public var options: CallOptions {
    return self.call.options
  }

  /// The path used to make the RPC.
  public var path: String {
    return self.call.path
  }

  /// Cancel this RPC if it hasn't already completed.
  public func cancel() {
    self.call.cancel(promise: nil)
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
    // We ignore messages in the closure and instead feed them into the response source when we
    // invoke the `call`.
    self.responseParts = StreamingResponseParts(on: call.eventLoop) { _ in }

    let backpressureStrategy = NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark(
      lowWatermark: 10,
      highWatermark: 50
    )
    let sequenceProducer = NIOThrowingAsyncSequenceProducer.makeSequence(
      elementType: Response.self,
      failureType: Error.self,
      backPressureStrategy: backpressureStrategy,
      delegate: GRPCAsyncSequenceProducerDelegate()
    )

    self.responseSource = sequenceProducer.source
    self.responseStream = .init(sequenceProducer.sequence)
  }

  /// We expose this as the only non-private initializer so that the caller
  /// knows that invocation is part of initialisation.
  internal static func makeAndInvoke(
    call: Call<Request, Response>,
    _ request: Request
  ) -> Self {
    let asyncCall = Self(call: call)

    asyncCall.call.invokeUnaryRequest(
      request,
      onStart: {},
      onError: { error in
        asyncCall.responseParts.handleError(error)
        asyncCall.responseSource.finish(error)
      },
      onResponsePart: AsyncCall.makeResponsePartHandler(
        responseParts: asyncCall.responseParts,
        responseSource: asyncCall.responseSource,
        requestStream: nil,
        requestType: Request.self
      )
    )

    return asyncCall
  }
}
