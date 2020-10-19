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
import Logging
import NIO
import SwiftProtobuf

/// A fake channel for use with generated test clients.
///
/// The `FakeChannel` provides factories for calls which avoid most of the gRPC stack and don't do
/// real networking. Each call relies on either a `FakeUnaryResponse` or a `FakeStreamingResponse`
/// to get responses or errors. The fake response of each type should be registered with the channel
/// prior to making a call via `makeFakeUnaryResponse` or `makeFakeStreamingResponse` respectively.
///
/// Users will typically not be required to interact with the channel directly, instead they should
/// do so via a generated test client.
public class FakeChannel: GRPCChannel {
  /// Fake response streams keyed by their path.
  private var responseStreams: [String: CircularBuffer<Any>]

  /// A logger.
  public let logger: Logger

  public init(logger: Logger = Logger(label: "io.grpc", factory: { _ in
    SwiftLogNoOpLogHandler()
  })) {
    self.responseStreams = [:]
    self.logger = logger
  }

  /// Make and store a fake unary response for the given path. Users should prefer making a response
  /// stream for their RPC directly via the appropriate method on their generated test client.
  public func makeFakeUnaryResponse<Request, Response>(
    path: String,
    requestHandler: @escaping (FakeRequestPart<Request>) -> Void
  ) -> FakeUnaryResponse<Request, Response> {
    let proxy = FakeUnaryResponse<Request, Response>(requestHandler: requestHandler)
    self.responseStreams[path, default: []].append(proxy)
    return proxy
  }

  /// Make and store a fake streaming response for the given path. Users should prefer making a
  /// response stream for their RPC directly via the appropriate method on their generated test
  /// client.
  public func makeFakeStreamingResponse<Request, Response>(
    path: String,
    requestHandler: @escaping (FakeRequestPart<Request>) -> Void
  ) -> FakeStreamingResponse<Request, Response> {
    let proxy = FakeStreamingResponse<Request, Response>(requestHandler: requestHandler)
    self.responseStreams[path, default: []].append(proxy)
    return proxy
  }

  /// Returns true if there are fake responses enqueued for the given path.
  public func hasFakeResponseEnqueued(forPath path: String) -> Bool {
    guard let noStreamsForPath = self.responseStreams[path]?.isEmpty else {
      return false
    }
    return !noStreamsForPath
  }

  public func makeCall<Request: Message, Response: Message>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> {
    return self._makeCall(
      path: path,
      type: type,
      callOptions: callOptions,
      interceptors: interceptors
    )
  }

  public func makeCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> {
    return self._makeCall(
      path: path,
      type: type,
      callOptions: callOptions,
      interceptors: interceptors
    )
  }

  private func _makeCall<Request, Response>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> {
    let stream: _FakeResponseStream<Request, Response>? = self.dequeueResponseStream(forPath: path)
    let eventLoop = stream?.channel.eventLoop ?? EmbeddedEventLoop()
    return Call(
      path: path,
      type: type,
      eventLoop: eventLoop,
      options: callOptions,
      interceptors: interceptors,
      transportFactory: .fake(stream, on: eventLoop)
    )
  }

  // (Docs inherited from `GRPCChannel`)
  public func makeUnaryCall<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    path: String,
    request: Request,
    callOptions: CallOptions
  ) -> UnaryCall<Request, Response> {
    return self.makeUnaryCall(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      path: path,
      request: request,
      callOptions: callOptions
    )
  }

  // (Docs inherited from `GRPCChannel`)
  public func makeUnaryCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions
  ) -> UnaryCall<Request, Response> {
    return self.makeUnaryCall(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      path: path,
      request: request,
      callOptions: callOptions
    )
  }

  // (Docs inherited from `GRPCChannel`)
  public func makeServerStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    request: Request,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    return self.makeServerStreamingCall(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      path: path,
      request: request,
      callOptions: callOptions,
      handler: handler
    )
  }

  // (Docs inherited from `GRPCChannel`)
  public func makeServerStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    return self.makeServerStreamingCall(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      path: path,
      request: request,
      callOptions: callOptions,
      handler: handler
    )
  }

  // (Docs inherited from `GRPCChannel`)
  public func makeClientStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    callOptions: CallOptions
  ) -> ClientStreamingCall<Request, Response> {
    return self.makeClientStreamingCall(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      path: path,
      callOptions: callOptions
    )
  }

  // (Docs inherited from `GRPCChannel`)
  public func makeClientStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions
  ) -> ClientStreamingCall<Request, Response> {
    return self.makeClientStreamingCall(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      path: path,
      callOptions: callOptions
    )
  }

  // (Docs inherited from `GRPCChannel`)
  public func makeBidirectionalStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    return self.makeBidirectionalStreamingCall(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      path: path,
      callOptions: callOptions,
      handler: handler
    )
  }

  // (Docs inherited from `GRPCChannel`)
  public func makeBidirectionalStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    return self.makeBidirectionalStreamingCall(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      path: path,
      callOptions: callOptions,
      handler: handler
    )
  }

  public func close() -> EventLoopFuture<Void> {
    // We don't have anything to close.
    return EmbeddedEventLoop().makeSucceededFuture(())
  }
}

extension FakeChannel {
  /// Dequeue a proxy for the given path and casts it to the given type, if one exists.
  private func dequeueResponseStream<Stream>(
    forPath path: String,
    as: Stream.Type = Stream.self
  ) -> Stream? {
    guard var streams = self.responseStreams[path], !streams.isEmpty else {
      return nil
    }

    // This is fine: we know we're non-empty.
    let first = streams.removeFirst()
    self.responseStreams.updateValue(streams, forKey: path)

    return first as? Stream
  }

  private func makeRequestHead(path: String, callOptions: CallOptions) -> _GRPCRequestHead {
    return _GRPCRequestHead(
      scheme: "http",
      path: path,
      host: "localhost",
      options: callOptions,
      requestID: nil
    )
  }
}

extension FakeChannel {
  private func makeUnaryCall<Serializer: MessageSerializer, Deserializer: MessageDeserializer>(
    serializer: Serializer,
    deserializer: Deserializer,
    path: String,
    request: Serializer.Input,
    callOptions: CallOptions
  ) -> UnaryCall<Serializer.Input, Deserializer.Output> {
    let call = UnaryCall<Serializer.Input, Deserializer.Output>.make(
      serializer: serializer,
      deserializer: deserializer,
      fakeResponse: self.dequeueResponseStream(forPath: path),
      callOptions: callOptions,
      logger: self.logger
    )

    call.send(self.makeRequestHead(path: path, callOptions: callOptions), request: request)

    return call
  }

  private func makeClientStreamingCall<
    Serializer: MessageSerializer,
    Deserializer: MessageDeserializer
  >(
    serializer: Serializer,
    deserializer: Deserializer,
    path: String,
    callOptions: CallOptions
  ) -> ClientStreamingCall<Serializer.Input, Deserializer.Output> {
    let call = ClientStreamingCall<Serializer.Input, Deserializer.Output>.make(
      serializer: serializer,
      deserializer: deserializer,
      fakeResponse: self.dequeueResponseStream(forPath: path),
      callOptions: callOptions,
      logger: self.logger
    )

    call.sendHead(self.makeRequestHead(path: path, callOptions: callOptions))

    return call
  }

  private func makeServerStreamingCall<
    Serializer: MessageSerializer,
    Deserializer: MessageDeserializer
  >(
    serializer: Serializer,
    deserializer: Deserializer,
    path: String,
    request: Serializer.Input,
    callOptions: CallOptions,
    handler: @escaping (Deserializer.Output) -> Void
  ) -> ServerStreamingCall<Serializer.Input, Deserializer.Output> {
    let call = ServerStreamingCall<Serializer.Input, Deserializer.Output>.make(
      serializer: serializer,
      deserializer: deserializer,
      fakeResponse: self.dequeueResponseStream(forPath: path),
      callOptions: callOptions,
      logger: self.logger,
      responseHandler: handler
    )

    call.send(self.makeRequestHead(path: path, callOptions: callOptions), request: request)

    return call
  }

  private func makeBidirectionalStreamingCall<
    Serializer: MessageSerializer,
    Deserializer: MessageDeserializer
  >(
    serializer: Serializer,
    deserializer: Deserializer,
    path: String,
    callOptions: CallOptions,
    handler: @escaping (Deserializer.Output) -> Void
  ) -> BidirectionalStreamingCall<Serializer.Input, Deserializer.Output> {
    let call = BidirectionalStreamingCall<Serializer.Input, Deserializer.Output>.make(
      serializer: serializer,
      deserializer: deserializer,
      fakeResponse: self.dequeueResponseStream(forPath: path),
      callOptions: callOptions,
      logger: self.logger,
      responseHandler: handler
    )

    call.sendHead(self.makeRequestHead(path: path, callOptions: callOptions))

    return call
  }
}
