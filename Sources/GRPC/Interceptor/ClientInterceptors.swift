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
import NIOCore

/// A base class for client interceptors.
///
/// Interceptors allow request and response parts to be observed, mutated or dropped as necessary.
/// The default behaviour for this base class is to forward any events to the next interceptor.
///
/// Interceptors may observe a number of different events:
/// - receiving response parts with `receive(_:context:)`,
/// - receiving errors with `errorCaught(_:context:)`,
/// - sending request parts with `send(_:promise:context:)`, and
/// - RPC cancellation with `cancel(context:)`.
///
/// These events flow through a pipeline of interceptors for each RPC. Request parts sent from the
/// call object (e.g. `UnaryCall`, `BidirectionalStreamingCall`) will traverse the pipeline in the
/// outbound direction from its tail via `send(_:context:)` eventually reaching the head of the
/// pipeline where it will be sent sent to the server.
///
/// Response parts, or errors, received from the transport fill be fired in the inbound direction
/// back through the interceptor pipeline via `receive(_:context:)` and `errorCaught(_:context:)`,
/// respectively. Note that the `end` response part and any error received are terminal: the
/// pipeline will be torn down once these parts reach the the tail and are a signal that the
/// interceptor should free up any resources it may be using.
///
/// Each of the interceptor functions is provided with a `context` which exposes analogous functions
/// (`receive(_:)`, `errorCaught(_:)`, `send(_:promise:)`, and `cancel(promise:)`) which may be
/// called to forward events to the next interceptor in the appropriate direction.
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

  /// Called when the interceptor has received an error.
  /// - Parameters:
  ///   - error: The error.
  ///   - context: An interceptor context which may be used to forward the error.
  open func errorCaught(
    _ error: Error,
    context: ClientInterceptorContext<Request, Response>
  ) {
    context.errorCaught(error)
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
