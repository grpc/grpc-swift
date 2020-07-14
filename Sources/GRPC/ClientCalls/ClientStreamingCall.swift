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
import NIO
import NIOHTTP2
import NIOHPACK
import Logging

/// A client-streaming gRPC call.
///
/// Messages should be sent via the `sendMessage` and `sendMessages` methods; the stream of messages
/// must be terminated by calling `sendEnd` to indicate the final message has been sent.
public final class ClientStreamingCall<RequestPayload, ResponsePayload>: StreamingRequestClientCall, UnaryResponseClientCall {
  private let transport: ChannelTransport<RequestPayload, ResponsePayload>

  /// The options used to make the RPC.
  public let options: CallOptions

  /// The `Channel` used to transport messages for this RPC.
  public var subchannel: EventLoopFuture<Channel> {
    return self.transport.streamChannel()
  }

  /// The `EventLoop` this call is running on.
  public var eventLoop: EventLoop {
    return self.transport.eventLoop
  }

  /// Cancel this RPC if it hasn't already completed.
  public func cancel(promise: EventLoopPromise<Void>?) {
    self.transport.cancel(promise: promise)
  }

  // MARK: - Response Parts

  /// The initial metadata returned from the server.
  public var initialMetadata: EventLoopFuture<HPACKHeaders> {
    if self.eventLoop.inEventLoop {
      return self.transport.responseContainer.lazyInitialMetadataPromise.getFutureResult()
    } else {
      return self.eventLoop.flatSubmit {
        return self.transport.responseContainer.lazyInitialMetadataPromise.getFutureResult()
      }
    }
  }

  /// The response returned by the server.
  public let response: EventLoopFuture<ResponsePayload>

  /// The trailing metadata returned from the server.
  public var trailingMetadata: EventLoopFuture<HPACKHeaders> {
    if self.eventLoop.inEventLoop {
      return self.transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult()
    } else {
      return self.eventLoop.flatSubmit {
        return self.transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult()
      }
    }
  }

  /// The final status of the the RPC.
  public var status: EventLoopFuture<GRPCStatus> {
    if self.eventLoop.inEventLoop {
      return self.transport.responseContainer.lazyStatusPromise.getFutureResult()
    } else {
      return self.eventLoop.flatSubmit {
        return self.transport.responseContainer.lazyStatusPromise.getFutureResult()
      }
    }
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
    let compressed = compression.isEnabled(callDefault: self.options.messageEncoding.enabledForRequests)
    let messageContext = _MessageContext(message, compressed: compressed)
    self.transport.sendRequest(.message(messageContext), promise: promise)
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
    let compressed = compression.isEnabled(callDefault: self.options.messageEncoding.enabledForRequests)
    self.transport.sendRequests(messages.map {
      .message(_MessageContext($0, compressed: compressed))
    }, promise: promise)
  }

  /// Terminates a stream of messages sent to the service.
  ///
  /// - Important: This should only ever be called once.
  /// - Parameter promise: A promise to be fulfilled when the end has been sent.
  public func sendEnd(promise: EventLoopPromise<Void>?) {
    self.transport.sendRequest(.end, promise: promise)
  }

  internal init(
    response: EventLoopFuture<ResponsePayload>,
    transport: ChannelTransport<RequestPayload, ResponsePayload>,
    options: CallOptions
  ) {
    self.response = response
    self.transport = transport
    self.options = options
  }

  internal func sendHead(_ head: _GRPCRequestHead) {
    self.transport.sendRequest(.head(head), promise: nil)
  }
}

extension ClientStreamingCall {
  internal static func makeOnHTTP2Stream<Serializer: MessageSerializer, Deserializer: MessageDeserializer>(
    multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>,
    serializer: Serializer,
    deserializer: Deserializer,
    callOptions: CallOptions,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger
  ) -> ClientStreamingCall<RequestPayload, ResponsePayload> where Serializer.Input == RequestPayload, Deserializer.Output == ResponsePayload {
    let eventLoop = multiplexer.eventLoop
    let responsePromise: EventLoopPromise<ResponsePayload> = eventLoop.makePromise()
    let transport = ChannelTransport<RequestPayload, ResponsePayload>(
      multiplexer: multiplexer,
      serializer: serializer,
      deserializer: deserializer,
      responseContainer: .init(eventLoop: eventLoop, unaryResponsePromise: responsePromise),
      callType: .clientStreaming,
      timeLimit: callOptions.timeLimit,
      errorDelegate: errorDelegate,
      logger: logger
    )
    return ClientStreamingCall(response: responsePromise.futureResult, transport: transport, options: callOptions)
  }

  internal static func make<Serializer: MessageSerializer, Deserializer: MessageDeserializer>(
    serializer: Serializer,
    deserializer: Deserializer,
    fakeResponse: FakeUnaryResponse<RequestPayload, ResponsePayload>?,
    callOptions: CallOptions,
    logger: Logger
  ) -> ClientStreamingCall<RequestPayload, ResponsePayload> where Serializer.Input == RequestPayload, Deserializer.Output == ResponsePayload {
    let eventLoop = fakeResponse?.channel.eventLoop ?? EmbeddedEventLoop()
    let responsePromise: EventLoopPromise<ResponsePayload> = eventLoop.makePromise()
    let responseContainer = ResponsePartContainer(eventLoop: eventLoop, unaryResponsePromise: responsePromise)

    let transport: ChannelTransport<RequestPayload, ResponsePayload>
    if let fakeResponse = fakeResponse {
      transport = .init(
        fakeResponse: fakeResponse,
        responseContainer: responseContainer,
        timeLimit: callOptions.timeLimit,
        logger: logger
      )

      fakeResponse.activate()
    } else {
      transport = .makeTransportForMissingFakeResponse(
        eventLoop: eventLoop,
        responseContainer: responseContainer,
        logger: logger
      )
    }

    return ClientStreamingCall(response: responsePromise.futureResult, transport: transport, options: callOptions)
  }

}
