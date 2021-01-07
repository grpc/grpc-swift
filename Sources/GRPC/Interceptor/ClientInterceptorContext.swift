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
import Logging
import NIO

public struct ClientInterceptorContext<Request, Response> {
  /// The interceptor this context is for.
  @usableFromInline
  internal let interceptor: ClientInterceptor<Request, Response>

  /// The pipeline this context is associated with.
  @usableFromInline
  internal let _pipeline: ClientInterceptorPipeline<Request, Response>

  /// The index of this context's interceptor within the pipeline.
  @usableFromInline
  internal let _index: Int

  /// The `EventLoop` this interceptor pipeline is being executed on.
  public var eventLoop: EventLoop {
    return self._pipeline.eventLoop
  }

  /// A logger.
  public var logger: Logger {
    return self._pipeline.logger
  }

  /// The type of the RPC, e.g. "unary".
  public var type: GRPCCallType {
    return self._pipeline.details.type
  }

  /// The path of the RPC in the format "/Service/Method", e.g. "/echo.Echo/Get".
  public var path: String {
    return self._pipeline.details.path
  }

  /// The options used to invoke the call.
  public var options: CallOptions {
    return self._pipeline.details.options
  }

  /// Construct a `ClientInterceptorContext` for the interceptor at the given index within in
  /// interceptor pipeline.
  @inlinable
  internal init(
    for interceptor: ClientInterceptor<Request, Response>,
    atIndex index: Int,
    in pipeline: ClientInterceptorPipeline<Request, Response>
  ) {
    self.interceptor = interceptor
    self._pipeline = pipeline
    self._index = index
  }

  /// Forwards the response part to the next inbound interceptor in the pipeline, if there is one.
  ///
  /// - Parameter part: The response part to forward.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  public func receive(_ part: GRPCClientResponsePart<Response>) {
    self.eventLoop.assertInEventLoop()
    self._pipeline.invokeReceive(part, fromContextAtIndex: self._index)
  }

  /// Forwards the error to the next inbound interceptor in the pipeline, if there is one.
  ///
  /// - Parameter error: The error to forward.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  public func errorCaught(_ error: Error) {
    self.eventLoop.assertInEventLoop()
    self._pipeline.invokeErrorCaught(error, fromContextAtIndex: self._index)
  }

  /// Forwards the request part to the next outbound interceptor in the pipeline, if there is one.
  ///
  /// - Parameters:
  ///   - part: The request part to forward.
  ///   - promise: The promise the complete when the part has been written.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  public func send(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?
  ) {
    self.eventLoop.assertInEventLoop()
    self._pipeline.invokeSend(part, promise: promise, fromContextAtIndex: self._index)
  }

  /// Forwards a request to cancel the RPC to the next outbound interceptor in the pipeline.
  ///
  /// - Parameter promise: The promise to complete with the outcome of the cancellation request.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  public func cancel(promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()
    self._pipeline.invokeCancel(promise: promise, fromContextAtIndex: self._index)
  }
}
