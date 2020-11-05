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

/// A base class for server interceptors.
///
/// Interceptors allow request and response and response parts to be observed, mutated or dropped
/// as necessary. The default behaviour for this base class is to forward any events to the next
/// interceptor.
///
/// Interceptors may observe two different types of event:
/// - receiving request parts with `receive(_:context:)`,
/// - sending response parts with `send(_:promise:context:)`.
///
/// These events flow through a pipeline of interceptors for each RPC. Request parts will enter
/// the head of the interceptor pipeline once the request router has determined that there is a
/// service provider which is able to handle the request stream. Response parts from the service
/// provider enter the tail of the interceptor pipeline and will be sent to the client after
/// traversing the pipeline through to the head.
///
/// Each of the interceptor functions is provided with a `context` which exposes analogous functions
/// (`receive(_:)` and `send(_:promise:)`) which may be called to forward events to the next
/// interceptor.
///
/// ### Thread Safety
///
/// Functions on `context` are not thread safe and **must** be called on the `EventLoop` found on
/// the `context`. Since each interceptor is invoked on the same `EventLoop` this does not usually
/// require any extra attention. However, if work is done on a `DispatchQueue` or _other_
/// `EventLoop` then implementers should ensure that they use `context` from the correct
/// `EventLoop`.
open class ServerInterceptor<Request, Response> {
  public init() {}

  /// Called when the interceptor has received a request part to handle.
  /// - Parameters:
  ///   - part: The request part which has been received from the client.
  ///   - context: An interceptor context which may be used to forward the response part.
  open func receive(
    _ part: GRPCServerRequestPart<Request>,
    context: ServerInterceptorContext<Request, Response>
  ) {
    context.receive(part)
  }

  /// Called when the interceptor has received a response part to handle.
  /// - Parameters:
  ///   - part: The request part which should be sent to the client.
  ///   - promise: A promise which should be completed when the response part has been written.
  ///   - context: An interceptor context which may be used to forward the request part.
  open func send(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?,
    context: ServerInterceptorContext<Request, Response>
  ) {
    context.send(part, promise: promise)
  }
}

// MARK: Head/Tail

/// An interceptor which offloads requests to the service provider and forwards any response parts
/// to the rest of the pipeline.
internal struct TailServerInterceptor<Request, Response> {
  /// Called when a request part has been received.
  private let onRequestPart: (GRPCServerRequestPart<Request>) -> Void

  init(
    _ onRequestPart: @escaping (GRPCServerRequestPart<Request>) -> Void
  ) {
    self.onRequestPart = onRequestPart
  }

  internal func receive(
    _ part: GRPCServerRequestPart<Request>,
    context: ServerInterceptorContext<Request, Response>
  ) {
    self.onRequestPart(part)
  }

  internal func send(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?,
    context: ServerInterceptorContext<Request, Response>
  ) {
    context.send(part, promise: promise)
  }
}

internal struct HeadServerInterceptor<Request, Response> {
  /// The pipeline this interceptor belongs to.
  private let pipeline: ServerInterceptorPipeline<Request, Response>

  /// Called when a response part has been received.
  private let onResponsePart: (GRPCServerResponsePart<Response>, EventLoopPromise<Void>?) -> Void

  internal init(
    for pipeline: ServerInterceptorPipeline<Request, Response>,
    _ onResponsePart: @escaping (GRPCServerResponsePart<Response>, EventLoopPromise<Void>?) -> Void
  ) {
    self.pipeline = pipeline
    self.onResponsePart = onResponsePart
  }

  internal func receive(
    _ part: GRPCServerRequestPart<Request>,
    context: ServerInterceptorContext<Request, Response>
  ) {
    context.receive(part)
  }

  internal func send(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?,
    context: ServerInterceptorContext<Request, Response>
  ) {
    // Close the pipeline on end.
    switch part {
    case .metadata, .message:
      ()
    case .end:
      self.pipeline.close()
    }
    self.onResponsePart(part, promise)
  }
}

// MARK: - Any Interceptor

/// A wrapping interceptor which delegates to the implementation of an underlying interceptor.
internal struct AnyServerInterceptor<Request, Response> {
  internal enum Implementation {
    case head(HeadServerInterceptor<Request, Response>)
    case tail(TailServerInterceptor<Request, Response>)
    case base(ServerInterceptor<Request, Response>)
  }

  /// The underlying interceptor implementation.
  internal let _implementation: Implementation

  internal static func head(
    for pipeline: ServerInterceptorPipeline<Request, Response>,
    _ onResponsePart: @escaping (GRPCServerResponsePart<Response>, EventLoopPromise<Void>?) -> Void
  ) -> AnyServerInterceptor<Request, Response> {
    return .init(.head(.init(for: pipeline, onResponsePart)))
  }

  internal static func tail(
    _ onRequestPart: @escaping (GRPCServerRequestPart<Request>) -> Void
  ) -> AnyServerInterceptor<Request, Response> {
    return .init(.tail(.init(onRequestPart)))
  }

  /// A user provided interceptor.
  /// - Parameter interceptor: The interceptor to wrap.
  /// - Returns: An `AnyServerInterceptor` which wraps `interceptor`.
  internal static func userProvided(
    _ interceptor: ServerInterceptor<Request, Response>
  ) -> AnyServerInterceptor<Request, Response> {
    return .init(.base(interceptor))
  }

  private init(_ implementation: Implementation) {
    self._implementation = implementation
  }

  internal func receive(
    _ part: GRPCServerRequestPart<Request>,
    context: ServerInterceptorContext<Request, Response>
  ) {
    switch self._implementation {
    case let .head(interceptor):
      interceptor.receive(part, context: context)
    case let .tail(interceptor):
      interceptor.receive(part, context: context)
    case let .base(interceptor):
      interceptor.receive(part, context: context)
    }
  }

  internal func send(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?,
    context: ServerInterceptorContext<Request, Response>
  ) {
    switch self._implementation {
    case let .head(interceptor):
      interceptor.send(part, promise: promise, context: context)
    case let .tail(interceptor):
      interceptor.send(part, promise: promise, context: context)
    case let .base(interceptor):
      interceptor.send(part, promise: promise, context: context)
    }
  }
}
