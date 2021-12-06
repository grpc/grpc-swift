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
#if compiler(>=5.5) && canImport(_Concurrency)

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

// MARK: - "Simple, but safe" wrappers.

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension GRPCClient {
  public func performAsyncUnaryCall<Request: Message, Response: Message>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    return try await self.channel.makeAsyncUnaryCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    ).response
  }

  public func performAsyncUnaryCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    return try await self.channel.makeAsyncUnaryCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    ).response
  }

  public func performAsyncServerStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncResponseStream<Response> {
    return self.channel.makeAsyncServerStreamingCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    ).responseStream
  }

  public func performAsyncServerStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncResponseStream<Response> {
    return self.channel.makeAsyncServerStreamingCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    ).responseStream
  }

  public func performAsyncClientStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message,
    RequestStream
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) async throws -> Response
    where RequestStream: AsyncSequence, RequestStream.Element == Request {
    let call = self.channel.makeAsyncClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return try await self.perform(call, with: requests)
  }

  public func performAsyncClientStreamingCall<
    Request: GRPCPayload,
    Response: GRPCPayload,
    RequestStream
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) async throws -> Response
    where RequestStream: AsyncSequence, RequestStream.Element == Request {
    let call = self.channel.makeAsyncClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return try await self.perform(call, with: requests)
  }

  public func performAsyncClientStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message,
    RequestStream
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) async throws -> Response
    where RequestStream: Sequence, RequestStream.Element == Request {
    let call = self.channel.makeAsyncClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return try await self.perform(call, with: AsyncStream(wrapping: requests))
  }

  public func performAsyncClientStreamingCall<
    Request: GRPCPayload,
    Response: GRPCPayload,
    RequestStream
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) async throws -> Response
    where RequestStream: Sequence, RequestStream.Element == Request {
    let call = self.channel.makeAsyncClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return try await self.perform(call, with: AsyncStream(wrapping: requests))
  }

  public func performAsyncBidirectionalStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message,
    RequestStream: AsyncSequence
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncResponseStream<Response>
    where RequestStream.Element == Request {
    let call = self.channel.makeAsyncBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return self.perform(call, with: requests)
  }

  public func performAsyncBidirectionalStreamingCall<
    Request: GRPCPayload,
    Response: GRPCPayload,
    RequestStream: AsyncSequence
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncResponseStream<Response>
    where RequestStream.Element == Request {
    let call = self.channel.makeAsyncBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return self.perform(call, with: requests)
  }

  public func performAsyncBidirectionalStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message,
    RequestStream: Sequence
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncResponseStream<Response>
    where RequestStream.Element == Request {
    let call = self.channel.makeAsyncBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return self.perform(call, with: AsyncStream(wrapping: requests))
  }

  public func performAsyncBidirectionalStreamingCall<
    Request: GRPCPayload,
    Response: GRPCPayload,
    RequestStream: Sequence
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncResponseStream<Response>
    where RequestStream.Element == Request {
    let call = self.channel.makeAsyncBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return self.perform(call, with: AsyncStream(wrapping: requests))
  }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension GRPCClient {
  @inlinable
  internal func perform<Request, Response, RequestStream>(
    _ call: GRPCAsyncClientStreamingCall<Request, Response>,
    with requests: RequestStream
  ) async throws -> Response
    where RequestStream: AsyncSequence, RequestStream.Element == Request {
    // We use a detached task because we use cancellation to signal early, but successful exit.
    let requestsTask = Task.detached {
      try Task.checkCancellation()
      for try await request in requests {
        try Task.checkCancellation()
        try await call.requestStream.send(request)
      }
      try Task.checkCancellation()
      try await call.requestStream.finish()
      try Task.checkCancellation()
    }
    return try await withTaskCancellationHandler {
      // Await the response, which may come before the request stream is exhausted.
      let response = try await call.response
      // If we have a response, we can stop sending requests.
      requestsTask.cancel()
      // Return the response.
      return response
    } onCancel: {
      requestsTask.cancel()
      // If this outer task is cancelled then we should also cancel the RPC.
      Task.detached {
        try await call.cancel()
      }
    }
  }

  @inlinable
  internal func perform<Request, Response, RequestStream>(
    _ call: GRPCAsyncBidirectionalStreamingCall<Request, Response>,
    with requests: RequestStream
  )
    -> GRPCAsyncResponseStream<Response>
    where RequestStream: AsyncSequence, RequestStream.Element == Request {
    Task {
      try await withTaskCancellationHandler {
        try Task.checkCancellation()
        for try await request in requests {
          try Task.checkCancellation()
          try await call.requestStream.send(request)
        }
        try Task.checkCancellation()
        try await call.requestStream.finish()
      } onCancel: {
        Task.detached {
          try await call.cancel()
        }
      }
    }
    return call.responseStream
  }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AsyncStream {
  /// Create an `AsyncStream` from a regular (non-async) `Sequence`.
  ///
  /// - Note: This is just here to avoid duplicating the above two `perform(_:with:)` functions
  ///         for `Sequence`.
  fileprivate init<T>(wrapping sequence: T) where T: Sequence, T.Element == Element {
    self.init { continuation in
      var iterator = sequence.makeIterator()
      while let value = iterator.next() {
        continuation.yield(value)
      }
      continuation.finish()
    }
  }
}

#endif
