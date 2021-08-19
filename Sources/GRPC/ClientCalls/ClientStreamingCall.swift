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
import Logging
import NIOCore
import NIOHPACK
import NIOHTTP2

/// A client-streaming gRPC call.
///
/// Messages should be sent via the `sendMessage` and `sendMessages` methods; the stream of messages
/// must be terminated by calling `sendEnd` to indicate the final message has been sent.
///
/// Note: while this object is a `struct`, its implementation delegates to `Call`. It therefore
/// has reference semantics.
public struct ClientStreamingCall<RequestPayload, ResponsePayload>: StreamingRequestClientCall,
  UnaryResponseClientCall {
  private let call: Call<RequestPayload, ResponsePayload>
  private let responseParts: UnaryResponseParts<ResponsePayload>

  /// The options used to make the RPC.
  public var options: CallOptions {
    return self.call.options
  }

  /// The path used to make the RPC.
  public var path: String {
    return self.call.path
  }

  /// The `Channel` used to transport messages for this RPC.
  public var subchannel: EventLoopFuture<Channel> {
    return self.call.channel
  }

  /// The `EventLoop` this call is running on.
  public var eventLoop: EventLoop {
    return self.call.eventLoop
  }

  /// Cancel this RPC if it hasn't already completed.
  public func cancel(promise: EventLoopPromise<Void>?) {
    self.call.cancel(promise: promise)
  }

  // MARK: - Response Parts

  /// The initial metadata returned from the server.
  public var initialMetadata: EventLoopFuture<HPACKHeaders> {
    return self.responseParts.initialMetadata
  }

  /// The response returned by the server.
  public var response: EventLoopFuture<ResponsePayload> {
    return self.responseParts.response
  }

  /// The trailing metadata returned from the server.
  public var trailingMetadata: EventLoopFuture<HPACKHeaders> {
    return self.responseParts.trailingMetadata
  }

  /// The final status of the the RPC.
  public var status: EventLoopFuture<GRPCStatus> {
    return self.responseParts.status
  }

  internal init(call: Call<RequestPayload, ResponsePayload>) {
    self.call = call
    self.responseParts = UnaryResponseParts(on: call.eventLoop)
  }

  internal func invoke() {
    self.call.invokeStreamingRequests(
      onError: self.responseParts.handleError(_:),
      onResponsePart: self.responseParts.handle(_:)
    )
  }

  // MARK: - Request

  /// Sends a message to the service.
  ///
  /// - Important: Callers must terminate the stream of messages by calling `sendEnd()` or
  ///   `sendEnd(promise:)`.
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - compression: Whether compression should be used for this message. Ignored if compression
  ///     was not enabled for the RPC.
  ///   - promise: A promise to fulfill with the outcome of the send operation.
  public func sendMessage(
    _ message: RequestPayload,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) {
    let compress = self.call.compress(compression)
    self.call.send(.message(message, .init(compress: compress, flush: true)), promise: promise)
  }

  /// Sends a sequence of messages to the service.
  ///
  /// - Important: Callers must terminate the stream of messages by calling `sendEnd()` or
  ///   `sendEnd(promise:)`.
  ///
  /// - Parameters:
  ///   - messages: The sequence of messages to send.
  ///   - compression: Whether compression should be used for this message. Ignored if compression
  ///     was not enabled for the RPC.
  ///   - promise: A promise to fulfill with the outcome of the send operation. It will only succeed
  ///     if all messages were written successfully.
  public func sendMessages<S>(
    _ messages: S,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) where S: Sequence, S.Element == RequestPayload {
    self.call.sendMessages(messages, compression: compression, promise: promise)
  }

  /// Terminates a stream of messages sent to the service.
  ///
  /// - Important: This should only ever be called once.
  /// - Parameter promise: A promise to be fulfilled when the end has been sent.
  public func sendEnd(promise: EventLoopPromise<Void>?) {
    self.call.send(.end, promise: promise)
  }
}
