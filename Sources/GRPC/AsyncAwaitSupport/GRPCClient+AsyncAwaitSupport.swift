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
#if compiler(>=5.6)

import SwiftProtobuf

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCClient {
  public func makeAsyncUnaryCall<Request: Message & Sendable, Response: Message & Sendable>(
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

  public func makeAsyncUnaryCall<Request: GRPCPayload & Sendable, Response: GRPCPayload & Sendable>(
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
    Request: SwiftProtobuf.Message & Sendable,
    Response: SwiftProtobuf.Message & Sendable
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

  public func makeAsyncServerStreamingCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable
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

  public func makeAsyncClientStreamingCall<
    Request: SwiftProtobuf.Message & Sendable,
    Response: SwiftProtobuf.Message & Sendable
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

  public func makeAsyncClientStreamingCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable
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

  public func makeAsyncBidirectionalStreamingCall<
    Request: SwiftProtobuf.Message & Sendable,
    Response: SwiftProtobuf.Message & Sendable
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
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable
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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCClient {
  public func performAsyncUnaryCall<Request: Message & Sendable, Response: Message & Sendable>(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    let call = self.channel.makeAsyncUnaryCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )

    return try await withTaskCancellationHandler {
      try await call.response
    } onCancel: {
      call.cancel()
    }
  }

  public func performAsyncUnaryCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable
  >(
    path: String,
    request: Request,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    let call = self.channel.makeAsyncUnaryCall(
      path: path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )

    return try await withTaskCancellationHandler {
      try await call.response
    } onCancel: {
      call.cancel()
    }
  }

  public func performAsyncServerStreamingCall<
    Request: SwiftProtobuf.Message & Sendable,
    Response: SwiftProtobuf.Message & Sendable
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

  public func performAsyncServerStreamingCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable
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

  public func performAsyncClientStreamingCall<
    Request: SwiftProtobuf.Message & Sendable,
    Response: SwiftProtobuf.Message & Sendable,
    RequestStream: AsyncSequence & Sendable
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) async throws -> Response where RequestStream.Element == Request {
    let call = self.channel.makeAsyncClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return try await self.perform(call, with: requests)
  }

  public func performAsyncClientStreamingCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable,
    RequestStream: AsyncSequence & Sendable
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) async throws -> Response where RequestStream.Element == Request {
    let call = self.channel.makeAsyncClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return try await self.perform(call, with: requests)
  }

  public func performAsyncClientStreamingCall<
    Request: SwiftProtobuf.Message & Sendable,
    Response: SwiftProtobuf.Message & Sendable,
    RequestStream: Sequence
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) async throws -> Response where RequestStream.Element == Request {
    let call = self.channel.makeAsyncClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return try await self.perform(call, with: AsyncStream(wrapping: requests))
  }

  public func performAsyncClientStreamingCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable,
    RequestStream: Sequence
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) async throws -> Response where RequestStream.Element == Request {
    let call = self.channel.makeAsyncClientStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return try await self.perform(call, with: AsyncStream(wrapping: requests))
  }

  public func performAsyncBidirectionalStreamingCall<
    Request: SwiftProtobuf.Message & Sendable,
    Response: SwiftProtobuf.Message & Sendable,
    RequestStream: AsyncSequence & Sendable
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
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable,
    RequestStream: AsyncSequence & Sendable
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
    Request: SwiftProtobuf.Message & Sendable,
    Response: SwiftProtobuf.Message & Sendable,
    RequestStream: Sequence
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncResponseStream<Response> where RequestStream.Element == Request {
    let call = self.channel.makeAsyncBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return self.perform(call, with: AsyncStream(wrapping: requests))
  }

  public func performAsyncBidirectionalStreamingCall<
    Request: GRPCPayload & Sendable,
    Response: GRPCPayload & Sendable,
    RequestStream: Sequence
  >(
    path: String,
    requests: RequestStream,
    callOptions: CallOptions? = nil,
    interceptors: [ClientInterceptor<Request, Response>] = [],
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> GRPCAsyncResponseStream<Response> where RequestStream.Element == Request {
    let call = self.channel.makeAsyncBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: interceptors
    )
    return self.perform(call, with: AsyncStream(wrapping: requests))
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCClient {
  @inlinable
  internal func perform<
    Request: Sendable,
    Response: Sendable,
    RequestStream: AsyncSequence & Sendable
  >(
    _ call: GRPCAsyncClientStreamingCall<Request, Response>,
    with requests: RequestStream
  ) async throws -> Response where RequestStream.Element == Request {
    return try await withTaskCancellationHandler {
      Task {
        do {
          // `AsyncSequence`s are encouraged to co-operatively check for cancellation, and we will
          // cancel the call `onCancel` anyway, so there's no need to check here too.
          for try await request in requests {
            try await call.requestStream.send(request)
          }
          try await call.requestStream.finish()
        } catch {
          // If we throw then cancel the call. We will rely on the response throwing an appropriate
          // error below.
          call.cancel()
        }
      }

      return try await call.response
    } onCancel: {
      call.cancel()
    }
  }

  @inlinable
  internal func perform<
    Request: Sendable,
    Response: Sendable,
    RequestStream: AsyncSequence & Sendable
  >(
    _ call: GRPCAsyncBidirectionalStreamingCall<Request, Response>,
    with requests: RequestStream
  ) -> GRPCAsyncResponseStream<Response> where RequestStream.Element == Request {
    Task {
      do {
        try await withTaskCancellationHandler {
          // `AsyncSequence`s are encouraged to co-operatively check for cancellation, and we will
          // cancel the call `onCancel` anyway, so there's no need to check here too.
          for try await request in requests {
            try await call.requestStream.send(request)
          }
          try await call.requestStream.finish()
        } onCancel: {
          call.cancel()
        }
      } catch {
        call.cancel()
      }
    }

    return call.responseStream
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
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
