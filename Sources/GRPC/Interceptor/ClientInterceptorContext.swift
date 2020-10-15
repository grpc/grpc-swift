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
  private let interceptor: AnyClientInterceptor<Request, Response>

  /// The pipeline this context is associated with.
  private let pipeline: ClientInterceptorPipeline<Request, Response>

  /// The index of this context's interceptor within the pipeline.
  private let index: Int

  // The next context in the inbound direction, if one exists.
  private var nextInbound: ClientInterceptorContext<Request, Response>? {
    return self.pipeline.nextInboundContext(forIndex: self.index)
  }

  // The next context in the outbound direction, if one exists.
  private var nextOutbound: ClientInterceptorContext<Request, Response>? {
    return self.pipeline.nextOutboundContext(forIndex: self.index)
  }

  /// The `EventLoop` this interceptor pipeline is being executed on.
  public var eventLoop: EventLoop {
    return self.pipeline.eventLoop
  }

  /// A logger.
  public var logger: Logger {
    return self.pipeline.logger
  }

  /// Construct a `ClientInterceptorContext` for the interceptor at the given index within in
  /// interceptor pipeline.
  internal init(
    for interceptor: AnyClientInterceptor<Request, Response>,
    atIndex index: Int,
    in pipeline: ClientInterceptorPipeline<Request, Response>
  ) {
    self.interceptor = interceptor
    self.pipeline = pipeline
    self.index = index
  }

  /// Forwards the response part to the next inbound interceptor in the pipeline, if there is one.
  ///
  /// - Parameter part: The response part to forward.
  /// - Important: This *must* to be called from the `eventLoop`.
  public func read(_ part: ClientResponsePart<Response>) {
    self._read(part)
  }

  /// Forwards the request part to the next outbound interceptor in the pipeline, if there is one.
  ///
  /// - Parameters:
  ///   - part: The request part to forward.
  ///   - promise: The promise the complete when the part has been written.
  /// - Important: This *must* to be called from the `eventLoop`.
  public func write(
    _ part: ClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?
  ) {
    self._write(part, promise: promise)
  }

  /// Forwards a request to cancel the RPC to the next outbound interceptor in the pipeline.
  ///
  /// - Parameter promise: The promise to complete with the outcome of the cancellation request.
  /// - Important: This *must* to be called from the `eventLoop`.
  public func cancel(promise: EventLoopPromise<Void>?) {
    self._cancel(promise: promise)
  }
}

extension ClientInterceptorContext {
  private func _read(_ part: ClientResponsePart<Response>) {
    self.eventLoop.assertInEventLoop()
    self.nextInbound?.invokeRead(part)
  }

  private func _write(
    _ part: ClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?
  ) {
    self.eventLoop.assertInEventLoop()

    if let outbound = self.nextOutbound {
      outbound.invokeWrite(part, promise: promise)
    } else {
      promise?.fail(GRPCStatus(code: .unavailable, message: "The RPC has already completed"))
    }
  }

  private func _cancel(promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()

    if let outbound = self.nextOutbound {
      outbound.invokeCancel(promise: promise)
    } else {
      // The RPC has already been completed. Should cancellation fail?
      promise?.succeed(())
    }
  }

  internal func invokeRead(_ part: ClientResponsePart<Response>) {
    self.eventLoop.assertInEventLoop()
    self.interceptor.read(part, context: self)
  }

  internal func invokeWrite(_ part: ClientRequestPart<Request>, promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()
    self.interceptor.write(part, promise: promise, context: self)
  }

  internal func invokeCancel(promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()
    self.interceptor.cancel(promise: promise, context: self)
  }
}
