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

/// A base class for client interceptors.
///
/// Interceptors allow request and response and response parts to be observed, mutated or dropped
/// as necessary. The default behaviour for this base class is to forward any events to the next
/// interceptor.
///
/// Interceptors may observe three different types of event:
/// - receiving response parts with `receive(_:context:)`,
/// - sending request parts with `send(_:promise:context:)`, and
/// - RPC cancellation with `cancel(context:)`.
///
/// These events flow through a pipeline of interceptors for each RPC. Request parts sent from the
/// call object (such as `UnaryCall` and `BidirectionalStreamingCall`) will traverse the pipeline
/// from its tail via `send(_:context:)` eventually reaching the head of the pipeline where it will
/// be sent sent to the server.
///
/// Response parts, or errors, received from the transport fill be fired back through the
/// interceptor pipeline via `receive(_:context:)`. Note that the `end` and `error` response parts
/// are terminal: the pipeline will be torn down once these parts reach the the tail of the
/// pipeline.
///
/// Each of the interceptor functions is provided with a `context` which exposes analogous functions
/// (`receive(_:)`, `send(_:promise:)`, and `cancel(promise:)`) which may be called to forward
/// events to the next interceptor.
///
/// ### Thread Safety
///
/// Functions on `context` are not thread safe and **must** be called on the `EventLoop` found on
/// the `context`. Since each interceptor is invoked on the same `EventLoop` this does not usually
/// require any extra attention. However, if work is done on a `DispatchQueue` or _other_
/// `EventLoop` then implementers should ensure that they use `context` from the correct
/// `EventLoop`.
open class ClientInterceptor<Request, Response> {
  public init() {}

  /// Called when the interceptor has received a response part to handle.
  /// - Parameters:
  ///   - part: The response part which has been received from the server.
  ///   - context: An interceptor context which may be used to forward the response part.
  open func receive(
    _ part: GRPCClientResponsePart<Response>,
    context: ClientInterceptorContext<Request, Response>
  ) {
    context.receive(part)
  }

  /// Called when the interceptor has received a request part to handle.
  /// - Parameters:
  ///   - part: The request part which should be sent to the server.
  ///   - promise: A promise which should be completed when the response part has been handled.
  ///   - context: An interceptor context which may be used to forward the request part.
  open func send(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    context.send(part, promise: promise)
  }

  /// Called when the interceptor has received a request to cancel the RPC.
  /// - Parameters:
  ///   - promise: A promise which should be cancellation request has been handled.
  ///   - context: An interceptor context which may be used to forward the cancellation request.
  open func cancel(
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    context.cancel(promise: promise)
  }
}

// MARK: - Head/Tail

/// An interceptor which offloads requests to the transport and forwards any response parts to the
/// rest of the pipeline.
@usableFromInline
internal struct HeadClientInterceptor<Request, Response>: ClientInterceptorProtocol {
  /// Called when a cancellation has been requested.
  private let onCancel: (EventLoopPromise<Void>?) -> Void

  /// Called when a request part has been written.
  @usableFromInline
  internal let _onRequestPart: (GRPCClientRequestPart<Request>, EventLoopPromise<Void>?) -> Void

  init(
    onCancel: @escaping (EventLoopPromise<Void>?) -> Void,
    onRequestPart: @escaping (GRPCClientRequestPart<Request>, EventLoopPromise<Void>?) -> Void
  ) {
    self.onCancel = onCancel
    self._onRequestPart = onRequestPart
  }

  @inlinable
  internal func send(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    self._onRequestPart(part, promise)
  }

  internal func cancel(
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    self.onCancel(promise)
  }

  internal func receive(
    _ part: GRPCClientResponsePart<Response>,
    context: ClientInterceptorContext<Request, Response>
  ) {
    context.receive(part)
  }
}

/// An interceptor which offloads responses to a provided callback and forwards any requests parts
/// and cancellation requests to rest of the pipeline.
@usableFromInline
internal struct TailClientInterceptor<Request, Response>: ClientInterceptorProtocol {
  /// The pipeline this interceptor belongs to.
  private let pipeline: ClientInterceptorPipeline<Request, Response>

  /// A user-provided error delegate.
  private let errorDelegate: ClientErrorDelegate?

  /// A response part handler; typically this will complete some promises, for streaming responses
  /// it will also invoke a user-supplied handler. This closure may also be provided by the user.
  /// We need to be careful about re-entrancy.
  private let onResponsePart: (GRPCClientResponsePart<Response>) -> Void

  internal init(
    for pipeline: ClientInterceptorPipeline<Request, Response>,
    errorDelegate: ClientErrorDelegate?,
    _ onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) {
    self.pipeline = pipeline
    self.errorDelegate = errorDelegate
    self.onResponsePart = onResponsePart
  }

  internal func receive(
    _ part: GRPCClientResponsePart<Response>,
    context: ClientInterceptorContext<Request, Response>
  ) {
    switch part {
    case .metadata, .message:
      self.onResponsePart(part)

    case .end:
      // We're about to complete, close the pipeline before calling out via `onResponsePart`.
      self.pipeline.close()
      self.onResponsePart(part)

    case let .error(error):
      // We're about to complete, close the pipeline before calling out via the error delegate
      // or `onResponsePart`.
      self.pipeline.close()

      var unwrappedError: Error

      // Unwrap the error, if possible.
      if let errorContext = error as? GRPCError.WithContext {
        unwrappedError = errorContext.error
        self.errorDelegate?.didCatchError(
          errorContext.error,
          logger: context.logger,
          file: errorContext.file,
          line: errorContext.line
        )
      } else {
        unwrappedError = error
        self.errorDelegate?.didCatchErrorWithoutContext(
          error,
          logger: context.logger
        )
      }

      // Emit the unwrapped error.
      self.onResponsePart(.error(unwrappedError))
    }
  }

  @inlinable
  internal func send(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    context.send(part, promise: promise)
  }

  internal func cancel(
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    context.cancel(promise: promise)
  }
}

// MARK: - Any Interceptor

/// A wrapping interceptor which delegates to the implementation of an underlying interceptor.
@usableFromInline
internal struct AnyClientInterceptor<Request, Response>: ClientInterceptorProtocol {
  @usableFromInline
  internal enum Implementation {
    case head(HeadClientInterceptor<Request, Response>)
    case tail(TailClientInterceptor<Request, Response>)
    case base(ClientInterceptor<Request, Response>)
  }

  /// The underlying interceptor implementation.
  @usableFromInline
  internal let _implementation: Implementation

  /// Makes a head interceptor.
  /// - Returns: An `AnyClientInterceptor` which wraps a `HeadClientInterceptor`.
  internal static func head(
    onCancel: @escaping (EventLoopPromise<Void>?) -> Void,
    onRequestPart: @escaping (GRPCClientRequestPart<Request>, EventLoopPromise<Void>?) -> Void
  ) -> AnyClientInterceptor<Request, Response> {
    return .init(.head(.init(onCancel: onCancel, onRequestPart: onRequestPart)))
  }

  /// Makes a tail interceptor.
  /// - Parameters:
  ///   - pipeline: The pipeline the tail interceptor belongs to.
  ///   - errorDelegate: An error delegate.
  ///   - onResponsePart: A handler called for each response part received from the pipeline.
  /// - Returns: An `AnyClientInterceptor` which wraps a `TailClientInterceptor`.
  internal static func tail(
    for pipeline: ClientInterceptorPipeline<Request, Response>,
    errorDelegate: ClientErrorDelegate?,
    _ onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) -> AnyClientInterceptor<Request, Response> {
    let tail = TailClientInterceptor(for: pipeline, errorDelegate: errorDelegate, onResponsePart)
    return .init(.tail(tail))
  }

  /// A user provided interceptor.
  /// - Parameter interceptor: The interceptor to wrap.
  /// - Returns: An `AnyClientInterceptor` which wraps `interceptor`.
  internal static func userProvided(
    _ interceptor: ClientInterceptor<Request, Response>
  ) -> AnyClientInterceptor<Request, Response> {
    return .init(.base(interceptor))
  }

  private init(_ implementation: Implementation) {
    self._implementation = implementation
  }

  internal func receive(
    _ part: GRPCClientResponsePart<Response>,
    context: ClientInterceptorContext<Request, Response>
  ) {
    switch self._implementation {
    case let .head(handler):
      handler.receive(part, context: context)
    case let .tail(handler):
      handler.receive(part, context: context)
    case let .base(handler):
      handler.receive(part, context: context)
    }
  }

  @inlinable
  internal func send(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    switch self._implementation {
    case let .head(handler):
      handler.send(part, promise: promise, context: context)
    case let .tail(handler):
      handler.send(part, promise: promise, context: context)
    case let .base(handler):
      handler.send(part, promise: promise, context: context)
    }
  }

  internal func cancel(
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    switch self._implementation {
    case let .head(handler):
      handler.cancel(promise: promise, context: context)
    case let .tail(handler):
      handler.cancel(promise: promise, context: context)
    case let .base(handler):
      handler.cancel(promise: promise, context: context)
    }
  }
}
