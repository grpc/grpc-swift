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

/// A base class for server interceptors.
///
/// Interceptors allow request and response and response parts to be observed, mutated or dropped
/// as necessary. The default behaviour for this base class is to forward any events to the next
/// interceptor.
///
/// Interceptors may observe two different types of event:
/// - receiving request parts with ``receive(_:context:)``,
/// - sending response parts with ``send(_:promise:context:)``.
///
/// These events flow through a pipeline of interceptors for each RPC. Request parts will enter
/// the head of the interceptor pipeline once the request router has determined that there is a
/// service provider which is able to handle the request stream. Response parts from the service
/// provider enter the tail of the interceptor pipeline and will be sent to the client after
/// traversing the pipeline through to the head.
///
/// Each of the interceptor functions is provided with a `context` which exposes analogous functions
/// (``receive(_:context:)`` and ``send(_:promise:context:)``) which may be called to forward events to the next
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
