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
  @usableFromInline
  internal let interceptor: AnyServerInterceptor<Request, Response>

  /// The pipeline this context is associated with.
  @usableFromInline
  internal let _pipeline: ServerInterceptorPipeline<Request, Response>

  /// The index of this context's interceptor within the pipeline.
  @usableFromInline
  internal let _index: Int

  // The next context in the inbound direction, if one exists.
  @inlinable
  internal var _nextInbound: ServerInterceptorContext<Request, Response>? {
    return self._pipeline.nextInboundContext(forIndex: self._index)
  }

  // The next context in the outbound direction, if one exists.
  @inlinable
  internal var _nextOutbound: ServerInterceptorContext<Request, Response>? {
    return self._pipeline.nextOutboundContext(forIndex: self._index)
  }

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
    return self._pipeline.type
  }

  /// The path of the RPC in the format "/Service/Method", e.g. "/echo.Echo/Get".
  public var path: String {
    return self._pipeline.path
  }

  /// The address of the remote peer.
  public var remoteAddress: SocketAddress? {
    return self._pipeline.remoteAddress
  }

  /// A 'UserInfo' dictionary.
  ///
  /// - Important: While `UserInfo` has value-semantics, this property retrieves from, and sets a
  ///   reference wrapped `UserInfo`. The contexts passed to the service provider share the same
  ///   reference. As such this may be used as a mechanism to pass information between interceptors
  ///   and service providers.
  /// - Important: `userInfo` *must* be accessed from the context's `eventLoop` in order to ensure
  ///   thread-safety.
  public var userInfo: UserInfo {
    get {
      return self._pipeline.userInfoRef.value
    }
    nonmutating set {
      self._pipeline.userInfoRef.value = newValue
    }
  }

  /// Construct a `ServerInterceptorContext` for the interceptor at the given index within the
  /// interceptor pipeline.
  @inlinable
  internal init(
    for interceptor: AnyServerInterceptor<Request, Response>,
    atIndex index: Int,
    in pipeline: ServerInterceptorPipeline<Request, Response>
  ) {
    self.interceptor = interceptor
    self._pipeline = pipeline
    self._index = index
  }

  /// Forwards the request part to the next inbound interceptor in the pipeline, if there is one.
  ///
  /// - Parameter part: The request part to forward.
  /// - Important: This *must* to be called from the `eventLoop`.
  public func receive(_ part: GRPCServerRequestPart<Request>) {
    self._nextInbound?.invokeReceive(part)
  }

  /// Forwards the response part to the next outbound interceptor in the pipeline, if there is one.
  ///
  /// - Parameters:
  ///   - part: The response part to forward.
  ///   - promise: The promise the complete when the part has been written.
  /// - Important: This *must* to be called from the `eventLoop`.
  public func send(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?
  ) {
    if let outbound = self._nextOutbound {
      outbound.invokeSend(part, promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }
}

extension ServerInterceptorContext {
  @inlinable
  internal func invokeReceive(_ part: GRPCServerRequestPart<Request>) {
    self.eventLoop.assertInEventLoop()
    self.interceptor.receive(part, context: self)
  }

  @inlinable
  internal func invokeSend(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?
  ) {
    self.eventLoop.assertInEventLoop()
    self.interceptor.send(part, promise: promise, context: self)
  }
}
