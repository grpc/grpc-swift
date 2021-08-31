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

import SwiftProtobuf

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension GRPCClient {
  public func makeAsyncUnaryCall<Request: Message, Response: Message>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncUnaryCall<Request, Response> {
    return self.channel.makeAsyncUnaryCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeAsyncUnaryCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncUnaryCall<Request, Response> {
    return self.channel.makeAsyncUnaryCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeAsyncServerStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncServerStreamingCall<Request, Response> {
    return self.channel.makeAsyncServerStreamingCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeAsyncServerStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncServerStreamingCall<Request, Response> {
    return self.channel.makeAsyncServerStreamingCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeAsyncClientStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncClientStreamingCall<Request, Response> {
    return self.channel.makeAsyncClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeAsyncClientStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncClientStreamingCall<Request, Response> {
    return self.channel.makeAsyncClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeAsyncBidirectionalStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncBidirectionalStreamingCall<Request, Response> {
    return self.channel.makeAsyncBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }

  public func makeAsyncBidirectionalStreamingCall<
    Request: GRPCPayload,
    Response: GRPCPayload
  >(
    path: String,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncBidirectionalStreamingCall<Request, Response> {
    return self.channel.makeAsyncBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
  }
}

#endif
