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
import SwiftProtobuf

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCChannel {
  /// Make a unary gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  internal func makeAsyncUnaryCall<
    Request: Message & Sendable,
    Response: Message & Sendable
  >(
    path: String,
    request: Request,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> GRPCAsyncUnaryCall<Request, Response> {
    return GRPCAsyncUnaryCall.makeAndInvoke(
      call: self.makeCall(
        path: path,
        type: .unary,
        callOptions: callOptions,
        interceptors: interceptors
      ),
      request
    )
  }

  /// Make a unary gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  internal func makeAsyncUnaryCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable
  >(
    path: String,
    request: Request,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> GRPCAsyncUnaryCall<Request, Response> {
    return GRPCAsyncUnaryCall.makeAndInvoke(
      call: self.makeCall(
        path: path,
        type: .unary,
        callOptions: callOptions,
        interceptors: interceptors
      ),
      request
    )
  }

  /// Makes a client-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  internal func makeAsyncClientStreamingCall<
    Request: Message & Sendable,
    Response: Message & Sendable
  >(
    path: String,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> GRPCAsyncClientStreamingCall<Request, Response> {
    return GRPCAsyncClientStreamingCall.makeAndInvoke(
      call: self.makeCall(
        path: path,
        type: .clientStreaming,
        callOptions: callOptions,
        interceptors: interceptors
      )
    )
  }

  /// Makes a client-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  internal func makeAsyncClientStreamingCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable
  >(
    path: String,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> GRPCAsyncClientStreamingCall<Request, Response> {
    return GRPCAsyncClientStreamingCall.makeAndInvoke(
      call: self.makeCall(
        path: path,
        type: .clientStreaming,
        callOptions: callOptions,
        interceptors: interceptors
      )
    )
  }

  /// Make a server-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  internal func makeAsyncServerStreamingCall<
    Request: Message & Sendable,
    Response: Message & Sendable
  >(
    path: String,
    request: Request,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> GRPCAsyncServerStreamingCall<Request, Response> {
    return GRPCAsyncServerStreamingCall.makeAndInvoke(
      call: self.makeCall(
        path: path,
        type: .serverStreaming,
        callOptions: callOptions,
        interceptors: interceptors
      ),
      request
    )
  }

  /// Make a server-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  internal func makeAsyncServerStreamingCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable
  >(
    path: String,
    request: Request,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> GRPCAsyncServerStreamingCall<Request, Response> {
    return GRPCAsyncServerStreamingCall.makeAndInvoke(
      call: self.makeCall(
        path: path,
        type: .serverStreaming,
        callOptions: callOptions,
        interceptors: []
      ),
      request
    )
  }

  /// Makes a bidirectional-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  internal func makeAsyncBidirectionalStreamingCall<
    Request: Message & Sendable,
    Response: Message & Sendable
  >(
    path: String,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> GRPCAsyncBidirectionalStreamingCall<Request, Response> {
    return GRPCAsyncBidirectionalStreamingCall.makeAndInvoke(
      call: self.makeCall(
        path: path,
        type: .bidirectionalStreaming,
        callOptions: callOptions,
        interceptors: interceptors
      )
    )
  }

  /// Makes a bidirectional-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  ///   - interceptors: A list of interceptors to intercept the request and response stream with.
  internal func makeAsyncBidirectionalStreamingCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable
  >(
    path: String,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>] = []
  ) -> GRPCAsyncBidirectionalStreamingCall<Request, Response> {
    return GRPCAsyncBidirectionalStreamingCall.makeAndInvoke(
      call: self.makeCall(
        path: path,
        type: .bidirectionalStreaming,
        callOptions: callOptions,
        interceptors: interceptors
      )
    )
  }
}
