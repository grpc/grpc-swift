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
import NIOSSL
import SwiftProtobuf

public protocol GRPCChannel {
  /// Makes a gRPC call on the channel with requests and responses conforming to
  /// `SwiftProtobuf.Message`.
  ///
  /// Note: this is a lower-level construct that any of `UnaryCall`, `ClientStreamingCall`,
  /// `ServerStreamingCall` or `BidirectionalStreamingCall` and does not have an API to protect
  /// users against protocol violations (such as sending to requests on a unary call).
  ///
  /// After making the `Call`, users must `invoke` the call with a callback which is invoked
  /// for each response part (or error) received. Any call to `send(_:promise:)` prior to calling
  /// `invoke` will fail and not be sent. Users are also responsible for closing the request stream
  /// by sending the `.end` request part.
  ///
  /// - Parameters:
  ///   - path: The path of the RPC, e.g. "/echo.Echo/get".
  ///   - type: The type of the RPC, e.g. `.unary`.
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  func makeCall<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response>

  /// Makes a gRPC call on the channel with requests and responses conforming to `GRPCPayload`.
  ///
  /// Note: this is a lower-level construct that any of `UnaryCall`, `ClientStreamingCall`,
  /// `ServerStreamingCall` or `BidirectionalStreamingCall` and does not have an API to protect
  /// users against protocol violations (such as sending to requests on a unary call).
  ///
  /// After making the `Call`, users must `invoke` the call with a callback which is invoked
  /// for each response part (or error) received. Any call to `send(_:promise:)` prior to calling
  /// `invoke` will fail and not be sent. Users are also responsible for closing the request stream
  /// by sending the `.end` request part.
  ///
  /// - Parameters:
  ///   - path: The path of the RPC, e.g. "/echo.Echo/get".
  ///   - type: The type of the RPC, e.g. `.unary`.
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  func makeCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response>

  /// Close the channel, and any connections associated with it.
  func close() -> EventLoopFuture<Void>
}

extension GRPCChannel {
  /// Make a unary gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  public func makeUnaryCall<Request: Message, Response: Message>(
    path: String,
    request: Request,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> UnaryCall<Request, Response> {
    let unary: UnaryCall<Request, Response> = UnaryCall(
      call: self.makeCall(
        path: path,
        type: .unary,
        callOptions: callOptions,
        interceptors: interceptors
      )
    )
    unary.invoke(request)
    return unary
  }

  /// Make a unary gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  public func makeUnaryCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> UnaryCall<Request, Response> {
    let rpc: UnaryCall<Request, Response> = UnaryCall(
      call: self.makeCall(
        path: path,
        type: .unary,
        callOptions: callOptions,
        interceptors: interceptors
      )
    )
    rpc.invoke(request)
    return rpc
  }

  /// Makes a client-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  public func makeClientStreamingCall<Request: Message, Response: Message>(
    path: String,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> ClientStreamingCall<Request, Response> {
    let rpc: ClientStreamingCall<Request, Response> = ClientStreamingCall(
      call: self.makeCall(
        path: path,
        type: .clientStreaming,
        callOptions: callOptions,
        interceptors: interceptors
      )
    )
    rpc.invoke()
    return rpc
  }

  /// Makes a client-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  public func makeClientStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> ClientStreamingCall<Request, Response> {
    let rpc: ClientStreamingCall<Request, Response> = ClientStreamingCall(
      call: self.makeCall(
        path: path,
        type: .clientStreaming,
        callOptions: callOptions,
        interceptors: interceptors
      )
    )
    rpc.invoke()
    return rpc
  }

  /// Make a server-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  ///   - handler: Response handler; called for every response received from the server.
  public func makeServerStreamingCall<Request: Message, Response: Message>(
    path: String,
    request: Request,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    let rpc: ServerStreamingCall<Request, Response> = ServerStreamingCall(
      call: self.makeCall(
        path: path,
        type: .serverStreaming,
        callOptions: callOptions,
        interceptors: interceptors
      ),
      callback: handler
    )
    rpc.invoke(request)
    return rpc
  }

  /// Make a server-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  ///   - handler: Response handler; called for every response received from the server.
  public func makeServerStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    let rpc: ServerStreamingCall<Request, Response> = ServerStreamingCall(
      call: self.makeCall(
        path: path,
        type: .serverStreaming,
        callOptions: callOptions,
        interceptors: []
      ),
      callback: handler
    )
    rpc.invoke(request)
    return rpc
  }

  /// Makes a bidirectional-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  ///   - handler: Response handler; called for every response received from the server.
  public func makeBidirectionalStreamingCall<Request: Message, Response: Message>(
    path: String,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    let rpc: BidirectionalStreamingCall<Request, Response> = BidirectionalStreamingCall(
      call: self.makeCall(
        path: path,
        type: .bidirectionalStreaming,
        callOptions: callOptions,
        interceptors: interceptors
      ),
      callback: handler
    )
    rpc.invoke()
    return rpc
  }

  /// Makes a bidirectional-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  ///   - handler: Response handler; called for every response received from the server.
  public func makeBidirectionalStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    let rpc: BidirectionalStreamingCall<Request, Response> = BidirectionalStreamingCall(
      call: self.makeCall(
        path: path,
        type: .bidirectionalStreaming,
        callOptions: callOptions,
        interceptors: interceptors
      ),
      callback: handler
    )
    rpc.invoke()
    return rpc
  }
}
