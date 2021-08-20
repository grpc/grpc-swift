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
import _NIOConcurrency
import Logging
import NIOCore
import NIOHPACK
import NIOHTTP2

#if compiler(>=5.5)

/// Async-await variant of BidirectionalStreamingCall.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct AsyncBidirectionalStreamingCall<
  RequestPayload,
  ResponsePayload
>: AsyncStreamingRequestClientCall {
  private let call: Call<RequestPayload, ResponsePayload>
  private let responseParts: StreamingResponseParts<ResponsePayload>
  public let responseStream: GRPCAsyncStream<ResponsePayload>

  /// The options used to make the RPC.
  public var options: CallOptions {
    return self.call.options
  }

  /// The `Channel` used to transport messages for this RPC.
  public var subchannel: Channel {
    get async throws {
      try await self.call.channel.get()
    }
  }

  /// Cancel this RPC if it hasn't already completed.
  public func cancel() async throws {
    try await self.call.cancel().get()
  }

  // MARK: - Response Parts

  /// The initial metadata returned from the server.
  public var initialMetadata: HPACKHeaders {
    get async throws {
      try await self.responseParts.initialMetadata.get()
    }
  }

  /// The trailing metadata returned from the server.
  public var trailingMetadata: HPACKHeaders {
    get async throws {
      try await self.responseParts.trailingMetadata.get()
    }
  }

  /// The final status of the the RPC.
  public var status: GRPCStatus {
    get async {
      try! await self.responseParts.status.get()
    }
  }

  private init(call: Call<RequestPayload, ResponsePayload>) {
    self.call = call
    // Initialise `responseParts` with an empty response handler because we
    // provide the responses as an AsyncSequence in `responseStream`.
    self.responseParts = StreamingResponseParts(on: call.eventLoop) { _ in }

    // Call and StreamingResponseParts are reference types so we grab a
    // referecence to them here to avoid capturing mutable self in the  closure
    // passed to the AsyncThrowingStream initializer.
    //
    // The alternative would be to declare the responseStream as:
    // ```
    // public private(set) var responseStream: AsyncThrowingStream<ResponsePayload>!
    // ```
    //
    // UPDATE: Additionally we expect to replace this soon with an AsyncSequence
    // implementation that supports yielding values from outside the closure.
    let call = self.call
    let responseParts = self.responseParts
    let responseStream = AsyncThrowingStream(ResponsePayload.self) { continuation in
      call.invokeStreamingRequests { error in
        responseParts.handleError(error)
        continuation.finish(throwing: error)
      } onResponsePart: { responsePart in
        responseParts.handle(responsePart)
        switch responsePart {
        case let .message(response): continuation.yield(response)
        case .metadata: break
        case .end: continuation.finish()
        }
      }
    }
    self.responseStream = .init(responseStream)
  }

  /// We expose this as the only non-private initializer so that the caller
  /// knows that invocation is part of initialisation.
  internal static func makeAndInvoke(call: Call<RequestPayload, ResponsePayload>) -> Self {
    Self(call: call)
  }

  // MARK: - Requests

  /// Sends a message to the service.
  ///
  /// - Important: Callers must terminate the stream of messages by calling `sendEnd()`.
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - compression: Whether compression should be used for this message. Ignored if compression
  ///     was not enabled for the RPC.
  public func sendMessage(
    _ message: RequestPayload,
    compression: Compression = .deferToCallDefault
  ) async throws {
    let compress = self.call.compress(compression)
    let promise = self.call.eventLoop.makePromise(of: Void.self)
    self.call.send(.message(message, .init(compress: compress, flush: true)), promise: promise)
    try await promise.futureResult.get()
  }

  /// Sends a sequence of messages to the service.
  ///
  /// - Important: Callers must terminate the stream of messages by calling `sendEnd()`.
  ///
  /// - Parameters:
  ///   - messages: The sequence of messages to send.
  ///   - compression: Whether compression should be used for this message. Ignored if compression
  ///     was not enabled for the RPC.
  public func sendMessages<S>(
    _ messages: S,
    compression: Compression = .deferToCallDefault
  ) async throws where S: Sequence, S.Element == RequestPayload {
    let promise = self.call.eventLoop.makePromise(of: Void.self)
    self.call.sendMessages(messages, compression: compression, promise: promise)
    try await promise.futureResult.get()
  }

  /// Terminates a stream of messages sent to the service.
  ///
  /// - Important: This should only ever be called once.
  public func sendEnd() async throws {
    let promise = self.call.eventLoop.makePromise(of: Void.self)
    self.call.send(.end, promise: promise)
    try await promise.futureResult.get()
  }
}

#endif
