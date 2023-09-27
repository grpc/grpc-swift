/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIOHTTP2

import protocol SwiftProtobuf.Message

/// A `ClientTransport` factory for an RPC.
@usableFromInline
internal struct ClientTransportFactory<Request, Response> {
  /// The underlying transport factory.
  private var factory: Factory

  @usableFromInline
  internal enum Factory {
    case http2(HTTP2ClientTransportFactory<Request, Response>)
    case fake(FakeClientTransportFactory<Request, Response>)
  }

  private init(_ http2: HTTP2ClientTransportFactory<Request, Response>) {
    self.factory = .http2(http2)
  }

  private init(_ fake: FakeClientTransportFactory<Request, Response>) {
    self.factory = .fake(fake)
  }

  /// Create a transport factory for HTTP/2 based transport with `SwiftProtobuf.Message` messages.
  /// - Parameters:
  ///   - multiplexer: The multiplexer used to create an HTTP/2 stream for the RPC.
  ///   - host: The value of the ":authority" pseudo header.
  ///   - scheme: The value of the ":scheme" pseudo header.
  ///   - errorDelegate: A client error delegate.
  /// - Returns: A factory for making and configuring HTTP/2 based transport.
  @usableFromInline
  internal static func http2(
    channel: EventLoopFuture<Channel>,
    authority: String,
    scheme: String,
    maximumReceiveMessageLength: Int,
    errorDelegate: ClientErrorDelegate?
  ) -> ClientTransportFactory<Request, Response>
  where
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  {
    let http2 = HTTP2ClientTransportFactory<Request, Response>(
      streamChannel: channel,
      scheme: scheme,
      authority: authority,
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      maximumReceiveMessageLength: maximumReceiveMessageLength,
      errorDelegate: errorDelegate
    )
    return .init(http2)
  }

  /// Create a transport factory for HTTP/2 based transport with `GRPCPayload` messages.
  /// - Parameters:
  ///   - multiplexer: The multiplexer used to create an HTTP/2 stream for the RPC.
  ///   - host: The value of the ":authority" pseudo header.
  ///   - scheme: The value of the ":scheme" pseudo header.
  ///   - errorDelegate: A client error delegate.
  /// - Returns: A factory for making and configuring HTTP/2 based transport.
  @usableFromInline
  internal static func http2(
    channel: EventLoopFuture<Channel>,
    authority: String,
    scheme: String,
    maximumReceiveMessageLength: Int,
    errorDelegate: ClientErrorDelegate?
  ) -> ClientTransportFactory<Request, Response> where Request: GRPCPayload, Response: GRPCPayload {
    let http2 = HTTP2ClientTransportFactory<Request, Response>(
      streamChannel: channel,
      scheme: scheme,
      authority: authority,
      serializer: AnySerializer(wrapping: GRPCPayloadSerializer()),
      deserializer: AnyDeserializer(wrapping: GRPCPayloadDeserializer()),
      maximumReceiveMessageLength: maximumReceiveMessageLength,
      errorDelegate: errorDelegate
    )
    return .init(http2)
  }

  /// Make a factory for 'fake' transport.
  /// - Parameter fakeResponse: The fake response stream.
  /// - Returns: A factory for making and configuring fake transport.
  @usableFromInline
  internal static func fake(
    _ fakeResponse: _FakeResponseStream<Request, Response>?
  ) -> ClientTransportFactory<Request, Response>
  where
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  {
    let factory = FakeClientTransportFactory(
      fakeResponse,
      requestSerializer: ProtobufSerializer(),
      requestDeserializer: ProtobufDeserializer(),
      responseSerializer: ProtobufSerializer(),
      responseDeserializer: ProtobufDeserializer()
    )
    return .init(factory)
  }

  /// Make a factory for 'fake' transport.
  /// - Parameter fakeResponse: The fake response stream.
  /// - Returns: A factory for making and configuring fake transport.
  @usableFromInline
  internal static func fake(
    _ fakeResponse: _FakeResponseStream<Request, Response>?
  ) -> ClientTransportFactory<Request, Response> where Request: GRPCPayload, Response: GRPCPayload {
    let factory = FakeClientTransportFactory(
      fakeResponse,
      requestSerializer: GRPCPayloadSerializer(),
      requestDeserializer: GRPCPayloadDeserializer(),
      responseSerializer: GRPCPayloadSerializer(),
      responseDeserializer: GRPCPayloadDeserializer()
    )
    return .init(factory)
  }

  /// Makes a configured `ClientTransport`.
  /// - Parameters:
  ///   - path: The path of the RPC, e.g. "/echo.Echo/Get".
  ///   - type: The type of RPC, e.g. `.unary`.
  ///   - options: Options for the RPC.
  ///   - interceptors: Interceptors to use for the RPC.
  ///   - onError: A callback invoked when an error is received.
  ///   - onResponsePart: A closure called for each response part received.
  /// - Returns: A configured transport.
  internal func makeConfiguredTransport(
    to path: String,
    for type: GRPCCallType,
    withOptions options: CallOptions,
    onEventLoop eventLoop: EventLoop,
    interceptedBy interceptors: [ClientInterceptor<Request, Response>],
    onStart: @escaping () -> Void,
    onError: @escaping (Error) -> Void,
    onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) -> ClientTransport<Request, Response> {
    switch self.factory {
    case let .http2(factory):
      let transport = factory.makeTransport(
        to: path,
        for: type,
        withOptions: options,
        onEventLoop: eventLoop,
        interceptedBy: interceptors,
        onStart: onStart,
        onError: onError,
        onResponsePart: onResponsePart
      )
      factory.configure(transport)
      return transport
    case let .fake(factory):
      let transport = factory.makeTransport(
        to: path,
        for: type,
        withOptions: options,
        onEventLoop: eventLoop,
        interceptedBy: interceptors,
        onError: onError,
        onResponsePart
      )
      factory.configure(transport)
      return transport
    }
  }
}

@usableFromInline
internal struct HTTP2ClientTransportFactory<Request, Response> {
  /// The multiplexer providing an HTTP/2 stream for the call.
  private var streamChannel: EventLoopFuture<Channel>

  /// The ":authority" pseudo-header.
  private var authority: String

  /// The ":scheme" pseudo-header.
  private var scheme: String

  /// An error delegate.
  private var errorDelegate: ClientErrorDelegate?

  /// The request serializer.
  private let serializer: AnySerializer<Request>

  /// The response deserializer.
  private let deserializer: AnyDeserializer<Response>

  /// Maximum allowed length of a received message.
  private let maximumReceiveMessageLength: Int

  @usableFromInline
  internal init<Serializer: MessageSerializer, Deserializer: MessageDeserializer>(
    streamChannel: EventLoopFuture<Channel>,
    scheme: String,
    authority: String,
    serializer: Serializer,
    deserializer: Deserializer,
    maximumReceiveMessageLength: Int,
    errorDelegate: ClientErrorDelegate?
  ) where Serializer.Input == Request, Deserializer.Output == Response {
    self.streamChannel = streamChannel
    self.scheme = scheme
    self.authority = authority
    self.serializer = AnySerializer(wrapping: serializer)
    self.deserializer = AnyDeserializer(wrapping: deserializer)
    self.maximumReceiveMessageLength = maximumReceiveMessageLength
    self.errorDelegate = errorDelegate
  }

  fileprivate func makeTransport(
    to path: String,
    for type: GRPCCallType,
    withOptions options: CallOptions,
    onEventLoop eventLoop: EventLoop,
    interceptedBy interceptors: [ClientInterceptor<Request, Response>],
    onStart: @escaping () -> Void,
    onError: @escaping (Error) -> Void,
    onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) -> ClientTransport<Request, Response> {
    return ClientTransport(
      details: self.makeCallDetails(type: type, path: path, options: options),
      eventLoop: eventLoop,
      interceptors: interceptors,
      serializer: self.serializer,
      deserializer: self.deserializer,
      errorDelegate: self.errorDelegate,
      onStart: onStart,
      onError: onError,
      onResponsePart: onResponsePart
    )
  }

  fileprivate func configure(_ transport: ClientTransport<Request, Response>) {
    transport.configure { _ in
      self.streamChannel.flatMapThrowing { channel in
        // This initializer will always occur on the appropriate event loop, sync operations are
        // fine here.
        let syncOperations = channel.pipeline.syncOperations

        do {
          let clientHandler = GRPCClientChannelHandler(
            callType: transport.callDetails.type,
            maximumReceiveMessageLength: self.maximumReceiveMessageLength,
            logger: transport.logger
          )
          try syncOperations.addHandler(clientHandler)
          try syncOperations.addHandler(transport)
        }
      }
    }
  }

  private func makeCallDetails(
    type: GRPCCallType,
    path: String,
    options: CallOptions
  ) -> CallDetails {
    return .init(
      type: type,
      path: path,
      authority: self.authority,
      scheme: self.scheme,
      options: options
    )
  }
}

@usableFromInline
internal struct FakeClientTransportFactory<Request, Response> {
  /// The fake response stream for the call. This can be `nil` if the user did not correctly
  /// configure their client. The result will be a transport which immediately fails.
  private var fakeResponseStream: _FakeResponseStream<Request, Response>?

  /// The request serializer.
  private let requestSerializer: AnySerializer<Request>

  /// The response deserializer.
  private let responseDeserializer: AnyDeserializer<Response>

  /// A codec for deserializing requests and serializing responses.
  private let codec: ChannelHandler

  @usableFromInline
  internal init<
    RequestSerializer: MessageSerializer,
    RequestDeserializer: MessageDeserializer,
    ResponseSerializer: MessageSerializer,
    ResponseDeserializer: MessageDeserializer
  >(
    _ fakeResponseStream: _FakeResponseStream<Request, Response>?,
    requestSerializer: RequestSerializer,
    requestDeserializer: RequestDeserializer,
    responseSerializer: ResponseSerializer,
    responseDeserializer: ResponseDeserializer
  )
  where
    RequestSerializer.Input == Request,
    RequestDeserializer.Output == Request,
    ResponseSerializer.Input == Response,
    ResponseDeserializer.Output == Response
  {
    self.fakeResponseStream = fakeResponseStream
    self.requestSerializer = AnySerializer(wrapping: requestSerializer)
    self.responseDeserializer = AnyDeserializer(wrapping: responseDeserializer)
    self.codec = GRPCClientReverseCodecHandler(
      serializer: responseSerializer,
      deserializer: requestDeserializer
    )
  }

  fileprivate func makeTransport(
    to path: String,
    for type: GRPCCallType,
    withOptions options: CallOptions,
    onEventLoop eventLoop: EventLoop,
    interceptedBy interceptors: [ClientInterceptor<Request, Response>],
    onError: @escaping (Error) -> Void,
    _ onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) -> ClientTransport<Request, Response> {
    return ClientTransport(
      details: CallDetails(
        type: type,
        path: path,
        authority: "localhost",
        scheme: "http",
        options: options
      ),
      eventLoop: eventLoop,
      interceptors: interceptors,
      serializer: self.requestSerializer,
      deserializer: self.responseDeserializer,
      errorDelegate: nil,
      onStart: {},
      onError: onError,
      onResponsePart: onResponsePart
    )
  }

  fileprivate func configure(_ transport: ClientTransport<Request, Response>) {
    transport.configure { handler in
      if let fakeResponse = self.fakeResponseStream {
        return fakeResponse.channel.pipeline.addHandlers(self.codec, handler).always { result in
          switch result {
          case .success:
            fakeResponse.activate()
          case .failure:
            ()
          }
        }
      } else {
        return transport.callEventLoop
          .makeFailedFuture(GRPCStatus(code: .unavailable, message: nil))
      }
    }
  }
}
