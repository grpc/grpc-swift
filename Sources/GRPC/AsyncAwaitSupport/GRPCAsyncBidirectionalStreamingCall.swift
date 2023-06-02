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

/// Async-await variant of ``BidirectionalStreamingCall``.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncBidirectionalStreamingCall<Request: Sendable, Response: Sendable>: Sendable {
  private let call: Call<Request, Response>
  private let responseParts: StreamingResponseParts<Response>
  private let responseSource: NIOThrowingAsyncSequenceProducer<
    Response,
    Error,
    NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
    GRPCAsyncSequenceProducerDelegate
  >.Source
  private let requestSink: AsyncSink<(Request, Compression)>

  /// A request stream writer for sending messages to the server.
  public let requestStream: GRPCAsyncRequestStreamWriter<Request>

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

  private func withRPCCancellation<R: Sendable>(_ fn: () async throws -> R) async rethrows -> R {
    return try await withTaskCancellationHandler(operation: fn) {
      self.cancel()
    }
  }

  /// The initial metadata returned from the server.
  ///
  /// - Important: The initial metadata will only be available when the first response has been
  /// received. However, it is not necessary for the response to have been consumed before reading
  /// this property.
  public var initialMetadata: HPACKHeaders {
    get async throws {
      try await self.withRPCCancellation {
        try await self.responseParts.initialMetadata.get()
      }
    }
  }

  /// The trailing metadata returned from the server.
  ///
  /// - Important: Awaiting this property will suspend until the responses have been consumed.
  public var trailingMetadata: HPACKHeaders {
    get async throws {
      try await self.withRPCCancellation {
        try await self.responseParts.trailingMetadata.get()
      }
    }
  }

  /// The final status of the the RPC.
  ///
  /// - Important: Awaiting this property will suspend until the responses have been consumed.
  public var status: GRPCStatus {
    get async {
      // force-try acceptable because any error is encapsulated in a successful GRPCStatus future.
      await self.withRPCCancellation {
        try! await self.responseParts.status.get()
      }
    }
  }

  private init(call: Call<Request, Response>) {
    self.call = call
    self.responseParts = StreamingResponseParts(on: call.eventLoop) { _ in }

    let sequenceProducer = NIOThrowingAsyncSequenceProducer<
      Response,
      Error,
      NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
      GRPCAsyncSequenceProducerDelegate
    >.makeSequence(
      backPressureStrategy: .init(lowWatermark: 10, highWatermark: 50),
      delegate: GRPCAsyncSequenceProducerDelegate()
    )

    self.responseSource = sequenceProducer.source
    self.responseStream = .init(sequenceProducer.sequence)
    let (requestStream, requestSink) = call.makeRequestStreamWriter()
    self.requestStream = requestStream
    self.requestSink = AsyncSink(wrapping: requestSink)
  }

  /// We expose this as the only non-private initializer so that the caller
  /// knows that invocation is part of initialisation.
  internal static func makeAndInvoke(call: Call<Request, Response>) -> Self {
    let asyncCall = Self(call: call)

    asyncCall.call.invokeStreamingRequests(
      onStart: {
        asyncCall.requestSink.setWritability(to: true)
      },
      onError: { error in
        asyncCall.responseParts.handleError(error)
        asyncCall.responseSource.finish(error)
        asyncCall.requestSink.finish(error: error)
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
    responseSource: NIOThrowingAsyncSequenceProducer<
      Response,
      Error,
      NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
      GRPCAsyncSequenceProducerDelegate
    >.Source,
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
          responseSource.finish(status)
        }
        requestStream?.finish(status)
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
      case let .end(status, _):
        requestStream?.finish(status)
      }
    }
  }
}
