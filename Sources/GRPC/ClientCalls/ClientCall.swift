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
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOHPACK
import SwiftProtobuf

/// Base protocol for a client call to a gRPC service.
public protocol ClientCall {
  /// The type of the request message for the call.
  associatedtype RequestPayload: GRPCPayload
  /// The type of the response message for the call.
  associatedtype ResponsePayload: GRPCPayload

  /// The options used to make the RPC.
  var options: CallOptions { get }

  /// HTTP/2 stream that requests and responses are sent and received on.
  var subchannel: EventLoopFuture<Channel> { get }

  /// Initial response metadata.
  var initialMetadata: EventLoopFuture<HPACKHeaders> { get }

  /// Status of this call which may be populated by the server or client.
  ///
  /// The client may populate the status if, for example, it was not possible to connect to the service.
  ///
  /// Note: despite `GRPCStatus` conforming to `Error`, the value will be __always__ delivered as a __success__
  /// result even if the status represents a __negative__ outcome. This future will __never__ be fulfilled
  /// with an error.
  var status: EventLoopFuture<GRPCStatus> { get }

  /// Trailing response metadata.
  var trailingMetadata: EventLoopFuture<HPACKHeaders> { get }

  /// Cancel the current call.
  ///
  /// Closes the HTTP/2 stream once it becomes available. Additional writes to the channel will be ignored.
  /// Any unfulfilled promises will be failed with a cancelled status (excepting `status` which will be
  /// succeeded, if not already succeeded).
  func cancel() -> EventLoopFuture<Void>
  func cancel(promise: EventLoopPromise<Void>?)
}

/// A `ClientCall` with request streaming; i.e. client-streaming and bidirectional-streaming.
public protocol StreamingRequestClientCall: ClientCall {
  /// Sends a message to the service.
  ///
  /// - Important: Callers must terminate the stream of messages by calling `sendEnd()` or `sendEnd(promise:)`.
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - compression: Whether compression should be used for this message. Ignored if compression
  ///     was not enabled for the RPC.
  /// - Returns: A future which will be fullfilled when the message has been sent.
  func sendMessage(_ message: RequestPayload, compression: Compression) -> EventLoopFuture<Void>

  /// Sends a message to the service.
  ///
  /// - Important: Callers must terminate the stream of messages by calling `sendEnd()` or `sendEnd(promise:)`.
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - compression: Whether compression should be used for this message. Ignored if compression
  ///     was not enabled for the RPC.
  ///   - promise: A promise to be fulfilled when the message has been sent.
  func sendMessage(_ message: RequestPayload, compression: Compression, promise: EventLoopPromise<Void>?)

  /// Sends a sequence of messages to the service.
  ///
  /// - Important: Callers must terminate the stream of messages by calling `sendEnd()` or `sendEnd(promise:)`.
  ///
  /// - Parameters:
  ///   - messages: The sequence of messages to send.
  ///   - compression: Whether compression should be used for this message. Ignored if compression
  ///     was not enabled for the RPC.
  func sendMessages<S: Sequence>(_ messages: S, compression: Compression) -> EventLoopFuture<Void> where S.Element == RequestPayload

  /// Sends a sequence of messages to the service.
  ///
  /// - Important: Callers must terminate the stream of messages by calling `sendEnd()` or `sendEnd(promise:)`.
  ///
  /// - Parameters:
  ///   - messages: The sequence of messages to send.
  ///   - compression: Whether compression should be used for this message. Ignored if compression
  ///     was not enabled for the RPC.
  ///   - promise: A promise to be fulfilled when all messages have been sent successfully.
  func sendMessages<S: Sequence>(_ messages: S, compression: Compression, promise: EventLoopPromise<Void>?) where S.Element == RequestPayload

  /// Returns a future which can be used as a message queue.
  ///
  /// Callers may use this as such:
  /// ```
  /// var queue = call.newMessageQueue()
  /// for message in messagesToSend {
  ///   queue = queue.then { call.sendMessage(message) }
  /// }
  /// ```
  ///
  /// - Returns: A future which may be used as the head of a message queue.
  func newMessageQueue() -> EventLoopFuture<Void>

  /// Terminates a stream of messages sent to the service.
  ///
  /// - Important: This should only ever be called once.
  /// - Returns: A future which will be fulfilled when the end has been sent.
  func sendEnd() -> EventLoopFuture<Void>

  /// Terminates a stream of messages sent to the service.
  ///
  /// - Important: This should only ever be called once.
  /// - Parameter promise: A promise to be fulfilled when the end has been sent.
  func sendEnd(promise: EventLoopPromise<Void>?)
}

/// A `ClientCall` with a unary response; i.e. unary and client-streaming.
public protocol UnaryResponseClientCall: ClientCall {
  /// The response message returned from the service if the call is successful. This may be failed
  /// if the call encounters an error.
  ///
  /// Callers should rely on the `status` of the call for the canonical outcome.
  var response: EventLoopFuture<ResponsePayload> { get }
}

extension StreamingRequestClientCall {
  public func sendMessage(
    _ message: RequestPayload,
    compression: Compression = .deferToCallDefault
  ) -> EventLoopFuture<Void> {
    return self.subchannel.flatMap { channel in
      let context = _MessageContext<RequestPayload>(
        message,
        compressed: compression.isEnabled(enabledOnCall: self.options.messageEncoding.enabledForRequests)
      )
      return channel.writeAndFlush(_GRPCClientRequestPart.message(context))
    }
  }

  public func sendMessage(
    _ message: RequestPayload,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) {
    self.subchannel.whenSuccess { channel in
      let context = _MessageContext<RequestPayload>(
        message,
        compressed: compression.isEnabled(enabledOnCall: self.options.messageEncoding.enabledForRequests)
      )
      channel.writeAndFlush(_GRPCClientRequestPart.message(context), promise: promise)
    }
  }

  public func sendMessages<S: Sequence>(
    _ messages: S,
    compression: Compression = .deferToCallDefault
  ) -> EventLoopFuture<Void> where S.Element == RequestPayload {
    return self.subchannel.flatMap { channel -> EventLoopFuture<Void> in
      let writeFutures = messages.map { message -> EventLoopFuture<Void> in
        let context = _MessageContext<RequestPayload>(
          message,
          compressed: compression.isEnabled(enabledOnCall: self.options.messageEncoding.enabledForRequests)
        )
        return channel.write(_GRPCClientRequestPart.message(context))
      }
      channel.flush()
      return EventLoopFuture.andAllSucceed(writeFutures, on: channel.eventLoop)
    }
  }

  public func sendMessages<S: Sequence>(
    _ messages: S,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) where S.Element == RequestPayload {
    if let promise = promise {
      self.sendMessages(messages).cascade(to: promise)
    } else {
      self.subchannel.whenSuccess { channel in
        for message in messages {
          let context = _MessageContext<RequestPayload>(
            message,
            compressed: compression.isEnabled(enabledOnCall: self.options.messageEncoding.enabledForRequests)
          )
          channel.write(_GRPCClientRequestPart.message(context), promise: nil)
        }
        channel.flush()
      }
    }
  }

  public func sendEnd() -> EventLoopFuture<Void> {
    return self.subchannel.flatMap { channel in
      return channel.writeAndFlush(_GRPCClientRequestPart<RequestPayload>.end)
    }
  }

  public func sendEnd(promise: EventLoopPromise<Void>?) {
    self.subchannel.whenSuccess { channel in
      channel.writeAndFlush(_GRPCClientRequestPart<RequestPayload>.end, promise: promise)
    }
  }
}
