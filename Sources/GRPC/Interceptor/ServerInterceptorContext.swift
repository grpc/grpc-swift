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

public struct ServerInterceptorContext<Request, Response> {
  /// The interceptor this context is for.
  internal let interceptor: AnyServerInterceptor<Request, Response>

  /// The pipeline this context is associated with.
  private let pipeline: ServerInterceptorPipeline<Request, Response>

  /// The index of this context's interceptor within the pipeline.
  private let index: Int

  // The next context in the inbound direction, if one exists.
  private var nextInbound: ServerInterceptorContext<Request, Response>? {
    return self.pipeline.nextInboundContext(forIndex: self.index)
  }

  // The next context in the outbound direction, if one exists.
  private var nextOutbound: ServerInterceptorContext<Request, Response>? {
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

  /// The type of the RPC, e.g. "unary".
  public var type: GRPCCallType {
    return self.pipeline.type
  }

  /// The path of the RPC in the format "/Service/Method", e.g. "/echo.Echo/Get".
  public var path: String {
    return self.pipeline.path
  }

  /// Construct a `ServerInterceptorContext` for the interceptor at the given index within the
  /// interceptor pipeline.
  internal init(
    for interceptor: AnyServerInterceptor<Request, Response>,
    atIndex index: Int,
    in pipeline: ServerInterceptorPipeline<Request, Response>
  ) {
    self.interceptor = interceptor
    self.pipeline = pipeline
    self.index = index
  }

  /// Forwards the request part to the next inbound interceptor in the pipeline, if there is one.
  ///
  /// - Parameter part: The request part to forward.
  /// - Important: This *must* to be called from the `eventLoop`.
  public func receive(_ part: ServerRequestPart<Request>) {
    self.nextInbound?.invokeReceive(part)
  }

  /// Forwards the response part to the next outbound interceptor in the pipeline, if there is one.
  ///
  /// - Parameters:
  ///   - part: The response part to forward.
  ///   - promise: The promise the complete when the part has been written.
  /// - Important: This *must* to be called from the `eventLoop`.
  public func send(
    _ part: ServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?
  ) {
    if let outbound = self.nextOutbound {
      outbound.invokeSend(part, promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }
}

extension ServerInterceptorContext {
  internal func invokeReceive(_ part: ServerRequestPart<Request>) {
    self.eventLoop.assertInEventLoop()
    self.interceptor.receive(part, context: self)
  }

  internal func invokeSend(_ part: ServerResponsePart<Response>, promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()
    self.interceptor.send(part, promise: promise, context: self)
  }
}
