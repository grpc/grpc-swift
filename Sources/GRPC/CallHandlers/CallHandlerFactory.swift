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
import SwiftProtobuf

// We can't use a 'where' clause on 'init's to constrain the generic requirements of a type. Instead
// we'll use static methods on this factory.
public enum CallHandlerFactory {
  public typealias UnaryContext<Response> = UnaryResponseCallContext<Response>
  public typealias UnaryEventObserver<Request, Response> = (Request) -> EventLoopFuture<Response>

  @available(*, deprecated, message: "Please regenerate your server code.")
  @inlinable
  public static func makeUnary<Request: Message, Response: Message>(
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<Request, Response>] = [],
    eventObserverFactory: @escaping (UnaryContext<Response>)
      -> UnaryEventObserver<Request, Response>
  ) -> UnaryCallHandler<ProtobufDeserializer<Request>, ProtobufSerializer<Response>> {
    return UnaryCallHandler(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      callHandlerContext: callHandlerContext,
      interceptors: interceptors,
      eventObserverFactory: eventObserverFactory
    )
  }

  @available(*, deprecated, message: "Please regenerate your server code.")
  @inlinable
  public static func makeUnary<Request: GRPCPayload, Response: GRPCPayload>(
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<Request, Response>] = [],
    eventObserverFactory: @escaping (UnaryContext<Response>)
      -> UnaryEventObserver<Request, Response>
  ) -> UnaryCallHandler<GRPCPayloadDeserializer<Request>, GRPCPayloadSerializer<Response>> {
    return UnaryCallHandler(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      callHandlerContext: callHandlerContext,
      interceptors: interceptors,
      eventObserverFactory: eventObserverFactory
    )
  }

  public typealias ClientStreamingContext<Response> = UnaryResponseCallContext<Response>
  public typealias ClientStreamingEventObserver<Request> =
    EventLoopFuture<(StreamEvent<Request>) -> Void>

  @available(*, deprecated, message: "Please regenerate your server code.")
  @inlinable
  public static func makeClientStreaming<Request: Message, Response: Message>(
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<Request, Response>] = [],
    eventObserverFactory: @escaping (ClientStreamingContext<Response>)
      -> ClientStreamingEventObserver<Request>
  ) -> ClientStreamingCallHandler<ProtobufDeserializer<Request>, ProtobufSerializer<Response>> {
    return ClientStreamingCallHandler(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      callHandlerContext: callHandlerContext,
      interceptors: interceptors,
      eventObserverFactory: eventObserverFactory
    )
  }

  @available(*, deprecated, message: "Please regenerate your server code.")
  @inlinable
  public static func makeClientStreaming<Request: GRPCPayload, Response: GRPCPayload>(
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<Request, Response>] = [],
    eventObserverFactory: @escaping (ClientStreamingContext<Response>)
      -> ClientStreamingEventObserver<Request>
  ) -> ClientStreamingCallHandler<
    GRPCPayloadDeserializer<Request>,
    GRPCPayloadSerializer<Response>
  > {
    return ClientStreamingCallHandler(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      callHandlerContext: callHandlerContext,
      interceptors: interceptors,
      eventObserverFactory: eventObserverFactory
    )
  }

  public typealias ServerStreamingContext<Response> = StreamingResponseCallContext<Response>
  public typealias ServerStreamingEventObserver<Request> = (Request) -> EventLoopFuture<GRPCStatus>

  @available(*, deprecated, message: "Please regenerate your server code.")
  @inlinable
  public static func makeServerStreaming<Request: Message, Response: Message>(
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<Request, Response>] = [],
    eventObserverFactory: @escaping (ServerStreamingContext<Response>)
      -> ServerStreamingEventObserver<Request>
  ) -> ServerStreamingCallHandler<ProtobufDeserializer<Request>, ProtobufSerializer<Response>> {
    return ServerStreamingCallHandler(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      callHandlerContext: callHandlerContext,
      interceptors: interceptors,
      eventObserverFactory: eventObserverFactory
    )
  }

  @available(*, deprecated, message: "Please regenerate your server code.")
  @inlinable
  public static func makeServerStreaming<Request: GRPCPayload, Response: GRPCPayload>(
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<Request, Response>] = [],
    eventObserverFactory: @escaping (ServerStreamingContext<Response>)
      -> ServerStreamingEventObserver<Request>
  ) -> ServerStreamingCallHandler<
    GRPCPayloadDeserializer<Request>,
    GRPCPayloadSerializer<Response>
  > {
    return ServerStreamingCallHandler(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      callHandlerContext: callHandlerContext,
      interceptors: interceptors,
      eventObserverFactory: eventObserverFactory
    )
  }

  public typealias BidirectionalStreamingContext<Response> = StreamingResponseCallContext<Response>
  public typealias BidirectionalStreamingEventObserver<Request> =
    EventLoopFuture<(StreamEvent<Request>) -> Void>

  @available(*, deprecated, message: "Please regenerate your server code.")
  @inlinable
  public static func makeBidirectionalStreaming<Request: Message, Response: Message>(
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<Request, Response>] = [],
    eventObserverFactory: @escaping (BidirectionalStreamingContext<Response>)
      -> BidirectionalStreamingEventObserver<Request>
  ) -> BidirectionalStreamingCallHandler<
    ProtobufDeserializer<Request>,
    ProtobufSerializer<Response>
  > {
    return BidirectionalStreamingCallHandler(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      callHandlerContext: callHandlerContext,
      interceptors: interceptors,
      eventObserverFactory: eventObserverFactory
    )
  }

  @available(*, deprecated, message: "Please regenerate your server code.")
  @inlinable
  public static func makeBidirectionalStreaming<Request: GRPCPayload, Response: GRPCPayload>(
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<Request, Response>] = [],
    eventObserverFactory: @escaping (BidirectionalStreamingContext<Response>)
      -> BidirectionalStreamingEventObserver<Request>
  ) -> BidirectionalStreamingCallHandler<
    GRPCPayloadDeserializer<Request>,
    GRPCPayloadSerializer<Response>
  > {
    return BidirectionalStreamingCallHandler(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      callHandlerContext: callHandlerContext,
      interceptors: interceptors,
      eventObserverFactory: eventObserverFactory
    )
  }
}
