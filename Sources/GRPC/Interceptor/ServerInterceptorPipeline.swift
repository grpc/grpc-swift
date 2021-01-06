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

  /// Called when a response part has traversed the interceptor pipeline.
  @usableFromInline
  internal let _onResponsePart: (GRPCServerResponsePart<Response>, EventLoopPromise<Void>?) -> Void

  /// Called when a request part has traversed the interceptor pipeline.
  @usableFromInline
  internal let _onRequestPart: (GRPCServerRequestPart<Request>) -> Void

  /// The index before the first user interceptor context index. (always -1).
  @usableFromInline
  internal let _headIndex: Int

  /// The index after the last user interceptor context index (i.e. 'userContext.endIndex').
  @usableFromInline
  internal let _tailIndex: Int

  /// Contexts for user provided interceptors.
  @usableFromInline
  internal var _userContexts: [ServerInterceptorContext<Request, Response>]

  /// Whether the interceptor pipeline is still open. It becomes closed after an 'end' response
  /// part has traversed the pipeline.
  @usableFromInline
  internal var _isOpen = true

  /// The index of the next context on the inbound side of the context at the given index.
  @inlinable
  internal func _nextInboundIndex(after index: Int) -> Int {
    // Unchecked arithmetic is okay here: our greatest inbound index is '_tailIndex' but we will
    // never ask for the inbound index after the tail.
    assert(self._indexIsValid(index))
    return index &+ 1
  }

  /// The index of the next context on the outbound side of the context at the given index.
  @inlinable
  internal func _nextOutboundIndex(after index: Int) -> Int {
    // Unchecked arithmetic is okay here: our lowest outbound index is '_headIndex' but we will
    // never ask for the outbound index after the head.
    assert(self._indexIsValid(index))
    return index &- 1
  }

  /// Returns true of the index is in the range `_headIndex ... _tailIndex`.
  @inlinable
  internal func _indexIsValid(_ index: Int) -> Bool {
    return self._headIndex <= index && index <= self._tailIndex
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

    self._onResponsePart = onResponsePart
    self._onRequestPart = onRequestPart

    // Head comes before user interceptors.
    self._headIndex = -1
    // Tail comes just after.
    self._tailIndex = interceptors.endIndex

    // Make some contexts.
    self._userContexts = []
    self._userContexts.reserveCapacity(interceptors.count)

    for index in 0 ..< interceptors.count {
      let context = ServerInterceptorContext(for: interceptors[index], atIndex: index, in: self)
      self._userContexts.append(context)
    }
  }

  /// Emit a request part message into the interceptor pipeline.
  ///
  /// - Parameter part: The part to emit into the pipeline.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func receive(_ part: GRPCServerRequestPart<Request>) {
    self._invokeReceive(part, onContextAtIndex: self._headIndex)
  }

  /// Invoke receive on the appropriate context when called from the context at the given index.
  @inlinable
  internal func invokeReceive(
    _ part: GRPCServerRequestPart<Request>,
    fromContextAtIndex index: Int
  ) {
    self._invokeReceive(part, onContextAtIndex: self._nextInboundIndex(after: index))
  }

  /// Invoke receive on the context at the given index, if doing so is safe.
  @inlinable
  internal func _invokeReceive(
    _ part: GRPCServerRequestPart<Request>,
    onContextAtIndex index: Int
  ) {
    self.eventLoop.assertInEventLoop()
    assert(self._indexIsValid(index))
    guard self._isOpen else {
      return
    }

    // We've checked the index.
    self._invokeReceive(part, onContextAtUncheckedIndex: index)
  }

  /// Invoke receive on the context at the given index, assuming that the index is valid and the
  /// pipeline is still open.
  @inlinable
  internal func _invokeReceive(
    _ part: GRPCServerRequestPart<Request>,
    onContextAtUncheckedIndex index: Int
  ) {
    switch index {
    case self._headIndex:
      // The next inbound index must exist, either for the tail or a user interceptor.
      self._invokeReceive(
        part,
        onContextAtUncheckedIndex: self._nextInboundIndex(after: self._headIndex)
      )

    case self._tailIndex:
      self._onRequestPart(part)

    default:
      self._userContexts[index].invokeReceive(part)
    }
  }

  /// Write a response message into the interceptor pipeline.
  ///
  /// - Parameters:
  ///   - part: The response part to sent.
  ///   - promise: A promise to complete when the response part has been successfully written.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func send(_ part: GRPCServerResponsePart<Response>, promise: EventLoopPromise<Void>?) {
    self._invokeSend(part, promise: promise, onContextAtIndex: self._tailIndex)
  }

  /// Invoke send on the appropriate context when called from the context at the given index.
  @inlinable
  internal func invokeSend(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?,
    fromContextAtIndex index: Int
  ) {
    self._invokeSend(
      part,
      promise: promise,
      onContextAtIndex: self._nextOutboundIndex(after: index)
    )
  }

  /// Invoke send on the context at the given index, if doing so is safe. Fails the `promise` if it
  /// is not safe to do so.
  @inlinable
  internal func _invokeSend(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?,
    onContextAtIndex index: Int
  ) {
    self.eventLoop.assertInEventLoop()
    assert(self._indexIsValid(index))
    guard self._isOpen else {
      promise?.fail(GRPCError.AlreadyComplete())
      return
    }

    self._invokeSend(uncheckedIndex: index, part, promise: promise)
  }

  /// Invoke send on the context at the given index, assuming that the index is valid and the
  /// pipeline is still open.
  @inlinable
  internal func _invokeSend(
    uncheckedIndex index: Int,
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?
  ) {
    switch index {
    case self._headIndex:
      if part.isEnd {
        self.close()
      }
      self._onResponsePart(part, promise)

    case self._tailIndex:
      // The next outbound index must exist: it will be the head or a user interceptor.
      self._invokeSend(
        uncheckedIndex: self._nextOutboundIndex(after: self._tailIndex),
        part,
        promise: promise
      )

    default:
      self._userContexts[index].invokeSend(part, promise: promise)
    }
  }

  @inlinable
  internal func close() {
    // We're no longer open.
    self._isOpen = false
    // Each context hold a ref to the pipeline; break the retain cycle.
    self._userContexts.removeAll()
  }
}

extension ServerInterceptorContext {
  @inlinable
  internal func invokeReceive(_ part: GRPCServerRequestPart<Request>) {
    self.interceptor.receive(part, context: self)
  }

  @inlinable
  internal func invokeSend(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?
  ) {
    self.interceptor.send(part, promise: promise, context: self)
  }
}
