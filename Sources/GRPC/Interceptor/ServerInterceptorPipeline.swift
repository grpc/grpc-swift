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

@usableFromInline
internal final class ServerInterceptorPipeline<Request, Response> {
  /// The `EventLoop` this RPC is being executed on.
  @usableFromInline
  internal let eventLoop: EventLoop

  /// The path of the RPC in the format "/Service/Method", e.g. "/echo.Echo/Get".
  @usableFromInline
  internal let path: String

  /// The type of the RPC, e.g. "unary".
  @usableFromInline
  internal let type: GRPCCallType

  /// The remote peer's address.
  @usableFromInline
  internal let remoteAddress: SocketAddress?

  /// A logger.
  @usableFromInline
  internal let logger: Logger

  /// A reference to a 'UserInfo'.
  @usableFromInline
  internal let userInfoRef: Ref<UserInfo>

  /// The contexts associated with the interceptors stored in this pipeline. Contexts will be
  /// removed once the RPC has completed. Contexts are ordered from inbound to outbound, that is,
  /// the head is first and the tail is last.
  @usableFromInline
  internal var _contexts: InterceptorContextList<ServerInterceptorContext<Request, Response>>?

  /// Returns the next context in the outbound direction for the context at the given index, if one
  /// exists.
  /// - Parameter index: The index of the `ServerInterceptorContext` which is requesting the next
  ///   outbound context.
  /// - Returns: The `ServerInterceptorContext` or `nil` if one does not exist.
  @inlinable
  internal func nextOutboundContext(
    forIndex index: Int
  ) -> ServerInterceptorContext<Request, Response>? {
    return self._context(atIndex: index - 1)
  }

  /// Returns the next context in the inbound direction for the context at the given index, if one
  /// exists.
  /// - Parameter index: The index of the `ServerInterceptorContext` which is requesting the next
  ///   inbound context.
  /// - Returns: The `ServerInterceptorContext` or `nil` if one does not exist.
  @inlinable
  internal func nextInboundContext(
    forIndex index: Int
  ) -> ServerInterceptorContext<Request, Response>? {
    return self._context(atIndex: index + 1)
  }

  /// Returns the context for the given index, if one exists.
  /// - Parameter index: The index of the `ServerInterceptorContext` to return.
  /// - Returns: The `ServerInterceptorContext` or `nil` if one does not exist for the given index.
  @inlinable
  internal func _context(atIndex index: Int) -> ServerInterceptorContext<Request, Response>? {
    return self._contexts?[checked: index]
  }

  /// The context closest to the `NIO.Channel`, i.e. where inbound events originate. This will be
  /// `nil` once the RPC has completed.
  @inlinable
  internal var head: ServerInterceptorContext<Request, Response>? {
    return self._contexts?.first
  }

  /// The context closest to the application, i.e. where outbound events originate. This will be
  /// `nil` once the RPC has completed.
  @inlinable
  internal var tail: ServerInterceptorContext<Request, Response>? {
    return self._contexts?.last
  }

  @inlinable
  internal init(
    logger: Logger,
    eventLoop: EventLoop,
    path: String,
    callType: GRPCCallType,
    remoteAddress: SocketAddress?,
    userInfoRef: Ref<UserInfo>,
    interceptors: [ServerInterceptor<Request, Response>],
    onRequestPart: @escaping (GRPCServerRequestPart<Request>) -> Void,
    onResponsePart: @escaping (GRPCServerResponsePart<Response>, EventLoopPromise<Void>?) -> Void
  ) {
    self.logger = logger
    self.eventLoop = eventLoop
    self.path = path
    self.type = callType
    self.remoteAddress = remoteAddress
    self.userInfoRef = userInfoRef

    // We need space for the head and tail as well as any user provided interceptors.
    self._contexts = InterceptorContextList(
      for: self,
      interceptors: interceptors,
      onRequestPart: onRequestPart,
      onResponsePart: onResponsePart
    )
  }

  /// Emit a request part message into the interceptor pipeline.
  ///
  /// - Parameter part: The part to emit into the pipeline.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func receive(_ part: GRPCServerRequestPart<Request>) {
    self.eventLoop.assertInEventLoop()
    self.head?.invokeReceive(part)
  }

  /// Write a response message into the interceptor pipeline.
  ///
  /// - Parameters:
  ///   - part: The response part to sent.
  ///   - promise: A promise to complete when the response part has been successfully written.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func send(_ part: GRPCServerResponsePart<Response>, promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()

    if let tail = self.tail {
      tail.invokeSend(part, promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  @inlinable
  internal func close() {
    self.eventLoop.assertInEventLoop()
    self._contexts = nil
  }
}

extension InterceptorContextList {
  @inlinable
  init<Request, Response>(
    for pipeline: ServerInterceptorPipeline<Request, Response>,
    interceptors: [ServerInterceptor<Request, Response>],
    onRequestPart: @escaping (GRPCServerRequestPart<Request>) -> Void,
    onResponsePart: @escaping (GRPCServerResponsePart<Response>, EventLoopPromise<Void>?) -> Void
  ) where Element == ServerInterceptorContext<Request, Response> {
    let middle = interceptors.enumerated().map { index, interceptor in
      ServerInterceptorContext(
        for: .userProvided(interceptor),
        atIndex: index,
        in: pipeline
      )
    }

    let first = ServerInterceptorContext<Request, Response>(
      for: .head(for: pipeline, onResponsePart),
      atIndex: middle.startIndex - 1,
      in: pipeline
    )

    let last = ServerInterceptorContext<Request, Response>(
      for: .tail(onRequestPart),
      atIndex: middle.endIndex,
      in: pipeline
    )

    self.init(first: first, middle: middle, last: last)
  }
}
