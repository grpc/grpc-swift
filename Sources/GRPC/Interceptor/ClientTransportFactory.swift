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
import NIO
import NIOHTTP2
import protocol SwiftProtobuf.Message

/// A `ClientTransport` factory for an RPC.
@usableFromInline
internal struct ClientTransportFactory<Request, Response> {
  /// The underlying transport factory.
  private var factory: Factory<Request, Response>

  private enum Factory<Request, Response> {
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
  internal static func http2<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>,
    authority: String,
    scheme: String,
    errorDelegate: ClientErrorDelegate?
  ) -> ClientTransportFactory<Request, Response> {
    let http2 = HTTP2ClientTransportFactory<Request, Response>(
      multiplexer: multiplexer,
      scheme: scheme,
      authority: authority,
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
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
  internal static func http2<Request: GRPCPayload, Response: GRPCPayload>(
    multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>,
    authority: String,
    scheme: String,
    errorDelegate: ClientErrorDelegate?
  ) -> ClientTransportFactory<Request, Response> {
    let http2 = HTTP2ClientTransportFactory<Request, Response>(
      multiplexer: multiplexer,
      scheme: scheme,
      authority: authority,
      serializer: AnySerializer(wrapping: GRPCPayloadSerializer()),
      deserializer: AnyDeserializer(wrapping: GRPCPayloadDeserializer()),
      errorDelegate: errorDelegate
    )
    return .init(http2)
  }

  /// Make a factory for 'fake' transport.
  /// - Parameter fakeResponse: The fake response stream.
  /// - Returns: A factory for making and configuring fake transport.
  internal static func fake<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    _ fakeResponse: _FakeResponseStream<Request, Response>?,
    on eventLoop: EventLoop
  ) -> ClientTransportFactory<Request, Response> {
    let factory = FakeClientTransportFactory(
      fakeResponse,
      on: eventLoop,
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
  internal static func fake<Request: GRPCPayload, Response: GRPCPayload>(
    _ fakeResponse: _FakeResponseStream<Request, Response>?,
    on eventLoop: EventLoop
  ) -> ClientTransportFactory<Request, Response> {
    let factory = FakeClientTransportFactory(
      fakeResponse,
      on: eventLoop,
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
    interceptedBy interceptors: [ClientInterceptor<Request, Response>],
    onError: @escaping (Error) -> Void,
    onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) -> ClientTransport<Request, Response> {
    switch self.factory {
    case let .http2(factory):
      let transport = factory.makeTransport(
        to: path,
        for: type,
        withOptions: options,
        interceptedBy: interceptors,
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
        interceptedBy: interceptors,
        onError: onError,
        onResponsePart
      )
      factory.configure(transport)
      return transport
    }
  }
}

private struct HTTP2ClientTransportFactory<Request, Response> {
  /// The multiplexer providing an HTTP/2 stream for the call.
  private var multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>

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

  fileprivate init<Serializer: MessageSerializer, Deserializer: MessageDeserializer>(
    multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>,
    scheme: String,
    authority: String,
    serializer: Serializer,
    deserializer: Deserializer,
    errorDelegate: ClientErrorDelegate?
  ) where Serializer.Input == Request, Deserializer.Output == Response {
    self.multiplexer = multiplexer
    self.scheme = scheme
    self.authority = authority
    self.serializer = AnySerializer(wrapping: serializer)
    self.deserializer = AnyDeserializer(wrapping: deserializer)
    self.errorDelegate = errorDelegate
  }

  fileprivate func makeTransport(
    to path: String,
    for type: GRPCCallType,
    withOptions options: CallOptions,
    interceptedBy interceptors: [ClientInterceptor<Request, Response>],
    onError: @escaping (Error) -> Void,
    onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) -> ClientTransport<Request, Response> {
    return ClientTransport(
      details: self.makeCallDetails(type: type, path: path, options: options),
      eventLoop: self.multiplexer.eventLoop,
      interceptors: interceptors,
      serializer: self.serializer,
      deserializer: self.deserializer,
      errorDelegate: self.errorDelegate,
      onError: onError,
      onResponsePart: onResponsePart
    )
  }

  fileprivate func configure<Request, Response>(_ transport: ClientTransport<Request, Response>) {
    transport.configure { _ in
      self.multiplexer.flatMap { multiplexer in
        let streamPromise = self.multiplexer.eventLoop.makePromise(of: Channel.self)

        multiplexer.createStreamChannel(promise: streamPromise) { streamChannel in
          // This initializer will always occur on the appropriate event loop, sync operations are
          // fine here.
          let syncOperations = streamChannel.pipeline.syncOperations

          do {
            let clientHandler = GRPCClientChannelHandler(
              callType: transport.callDetails.type,
              logger: transport.logger
            )
            try syncOperations.addHandler(clientHandler)
            try syncOperations.addHandler(transport)
          } catch {
            return streamChannel.eventLoop.makeFailedFuture(error)
          }

          return streamChannel.eventLoop.makeSucceededVoidFuture()
        }

        // We don't need the stream, but we do need to know it was correctly configured.
        return streamPromise.futureResult.map { _ in }
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

private struct FakeClientTransportFactory<Request, Response> {
  /// The fake response stream for the call. This can be `nil` if the user did not correctly
  /// configure their client. The result will be a transport which immediately fails.
  private var fakeResponseStream: _FakeResponseStream<Request, Response>?

  /// The `EventLoop` from the response stream, or an `EmbeddedEventLoop` should the response
  /// stream be `nil`.
  private var eventLoop: EventLoop

  /// The request serializer.
  private let requestSerializer: AnySerializer<Request>

  /// The response deserializer.
  private let responseDeserializer: AnyDeserializer<Response>

  /// A codec for deserializing requests and serializing responses.
  private let codec: ChannelHandler

  fileprivate init<
    RequestSerializer: MessageSerializer,
    RequestDeserializer: MessageDeserializer,
    ResponseSerializer: MessageSerializer,
    ResponseDeserializer: MessageDeserializer
  >(
    _ fakeResponseStream: _FakeResponseStream<Request, Response>?,
    on eventLoop: EventLoop,
    requestSerializer: RequestSerializer,
    requestDeserializer: RequestDeserializer,
    responseSerializer: ResponseSerializer,
    responseDeserializer: ResponseDeserializer
  ) where RequestSerializer.Input == Request,
    RequestDeserializer.Output == Request,
    ResponseSerializer.Input == Response,
    ResponseDeserializer.Output == Response
  {
    self.fakeResponseStream = fakeResponseStream
    self.eventLoop = eventLoop
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
      eventLoop: self.eventLoop,
      interceptors: interceptors,
      serializer: self.requestSerializer,
      deserializer: self.responseDeserializer,
      errorDelegate: nil,
      onError: onError,
      onResponsePart: onResponsePart
    )
  }

  fileprivate func configure<Request, Response>(_ transport: ClientTransport<Request, Response>) {
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
        return self.eventLoop.makeFailedFuture(GRPCStatus(code: .unavailable, message: nil))
      }
    }
  }
}
