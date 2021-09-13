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
#if compiler(>=5.5)

import NIOHPACK

/// Async-await variant of `ClientStreamingCall`.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct GRPCAsyncClientStreamingCall<Request, Response> {
  private let call: Call<Request, Response>
  private let responseParts: UnaryResponseParts<Response>

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
    // swiftformat:disable:next redundantGet
    get async throws {
      try await self.responseParts.initialMetadata.get()
    }
  }

  /// The response returned by the server.
  public var response: Response {
    // swiftformat:disable:next redundantGet
    get async throws {
      try await self.responseParts.response.get()
    }
  }

  /// The trailing metadata returned from the server.
  ///
  /// - Important: Awaiting this property will suspend until the responses have been consumed.
  public var trailingMetadata: HPACKHeaders {
    // swiftformat:disable:next redundantGet
    get async throws {
      try await self.responseParts.trailingMetadata.get()
    }
  }

  /// The final status of the the RPC.
  ///
  /// - Important: Awaiting this property will suspend until the responses have been consumed.
  public var status: GRPCStatus {
    // swiftformat:disable:next redundantGet
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
  }

  /// We expose this as the only non-private initializer so that the caller
  /// knows that invocation is part of initialisation.
  internal static func makeAndInvoke(call: Call<Request, Response>) -> Self {
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
    _ message: Request,
    compression: Compression = .deferToCallDefault
  ) async throws {
    let compress = self.call.compress(compression)
    let promise = self.call.eventLoop.makePromise(of: Void.self)
    self.call.send(.message(message, .init(compress: compress, flush: true)), promise: promise)
    // TODO: This waits for the message to be written to the socket. We should probably just wait for it to be written to the channel?
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
  ) async throws where S: Sequence, S.Element == Request {
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
