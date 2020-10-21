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
import NIOHPACK
import NIOHTTP2
import protocol SwiftProtobuf.Message

/// An object representing a single RPC from the perspective of a client. It allows the caller to
/// send request parts, request a cancellation, and receive response parts in a provided callback.
///
/// The call object sits atop an interceptor pipeline (see `ClientInterceptor`) which allows for
/// request and response streams to be arbitrarily transformed or observed. Requests sent via this
/// call will traverse the pipeline before reaching the network, and responses received will
/// traverse the pipeline having been received from the network.
///
/// This object is a lower-level API than the equivalent wrapped calls (such as `UnaryCall` and
/// `BidirectionalStreamingCall`). The caller is therefore required to do more in order to use this
/// object correctly. Callers must call `invoke(_:)` to start the call and ensure that the correct
/// number of request parts are sent in the correct order (exactly one `metadata`, followed
/// by at most one `message` for unary and server streaming calls, and any number of `message` parts
/// for client streaming and bidirectional streaming calls. All call types must terminate their
/// request stream by sending one `end` message.
///
/// Callers are not able to create `Call` objects directly, rather they must be created via an
/// object conforming to `GRPCChannel` such as `ClientConnection`.
public class Call<Request, Response> {
  @usableFromInline
  internal enum State {
    /// Idle, waiting to be invoked.
    case idle(ClientTransportFactory<Request, Response>)

    /// Invoked, we have a transport on which to send requests. The transport may be closed if the
    /// RPC has already completed.
    case invoked(ClientTransport<Request, Response>)
  }

  /// The current state of the call.
  @usableFromInline
  internal var _state: State

  /// User provided interceptors for the call.
  private let interceptors: [ClientInterceptor<Request, Response>]

  /// Whether compression is enabled on the call.
  private var isCompressionEnabled: Bool {
    return self.options.messageEncoding.enabledForRequests
  }

  /// The `EventLoop` the call is being invoked on.
  public let eventLoop: EventLoop

  /// The path of the RPC, usually generated from a service definition, e.g. "/echo.Echo/Get".
  public let path: String

  /// The type of the RPC, e.g. unary, bidirectional streaming.
  public let type: GRPCCallType

  /// Options used to invoke the call.
  public let options: CallOptions

  // Calls can't be constructed directly: users must make them using a `GRPCChannel`.
  internal init(
    path: String,
    type: GRPCCallType,
    eventLoop: EventLoop,
    options: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>],
    transportFactory: ClientTransportFactory<Request, Response>
  ) {
    self.path = path
    self.type = type
    self.options = options
    self._state = .idle(transportFactory)
    self.eventLoop = eventLoop
    self.interceptors = interceptors
  }

  /// Starts the call and provides a callback which is invoked on every response part received from
  /// the server.
  ///
  /// This must be called prior to `send(_:promise:)` or `cancel(promise:)`.
  ///
  /// - Parameter onResponsePart: A callback which is invoked on every response part.
  /// - Important: This function should only be called once. Subsequent calls will be ignored.
  @inlinable
  public func invoke(_ onResponsePart: @escaping (ClientResponsePart<Response>) -> Void) {
    self.options.logger.debug("starting rpc", metadata: ["path": "\(self.path)"], source: "GRPC")

    if self.eventLoop.inEventLoop {
      self._invoke(onResponsePart)
    } else {
      self.eventLoop.execute {
        self._invoke(onResponsePart)
      }
    }
  }

  /// Send a request part on the RPC.
  /// - Parameters:
  ///   - part: The request part to send.
  ///   - promise: A promise which will be completed when the request part has been handled.
  /// - Note: Sending will always fail if `invoke(_:)` has not been called.
  @inlinable
  public func send(_ part: ClientRequestPart<Request>, promise: EventLoopPromise<Void>?) {
    if self.eventLoop.inEventLoop {
      self._send(part, promise: promise)
    } else {
      self.eventLoop.execute {
        self._send(part, promise: promise)
      }
    }
  }

  /// Attempt to cancel the RPC.
  /// - Parameter promise: A promise which will be completed once the cancellation request has been
  ///   dealt with.
  /// - Note: Cancellation will always fail if `invoke(_:)` has not been called.
  public func cancel(promise: EventLoopPromise<Void>?) {
    if self.eventLoop.inEventLoop {
      self._cancel(promise: promise)
    } else {
      self.eventLoop.execute {
        self._cancel(promise: promise)
      }
    }
  }
}

extension Call {
  /// Send a request part on the RPC.
  /// - Parameter part: The request part to send.
  /// - Returns: A future which will be resolved when the request has been handled.
  /// - Note: Sending will always fail if `invoke(_:)` has not been called.
  @inlinable
  public func send(_ part: ClientRequestPart<Request>) -> EventLoopFuture<Void> {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.send(part, promise: promise)
    return promise.futureResult
  }

  /// Attempt to cancel the RPC.
  /// - Note: Cancellation will always fail if `invoke(_:)` has not been called.
  /// - Returns: A future which will be resolved when the cancellation request has been cancelled.
  public func cancel() -> EventLoopFuture<Void> {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.cancel(promise: promise)
    return promise.futureResult
  }
}

extension Call {
  /// Invoke the RPC with this response part handler.
  /// - Important: This *must* to be called from the `eventLoop`.
  @usableFromInline
  internal func _invoke(
    _ onResponsePart: @escaping (ClientResponsePart<Response>) -> Void
  ) {
    self.eventLoop.assertInEventLoop()

    switch self._state {
    case let .idle(factory):
      let transport = factory.makeConfiguredTransport(
        to: self.path,
        for: self.type,
        withOptions: self.options,
        interceptedBy: self.interceptors,
        onResponsePart
      )
      self._state = .invoked(transport)

    case .invoked:
      // We can't be invoked twice. Just ignore this.
      ()
    }
  }

  /// Send a request part on the transport.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func _send(_ part: ClientRequestPart<Request>, promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()

    switch self._state {
    case .idle:
      promise?.fail(GRPCError.InvalidState("Call must be invoked before sending request parts"))

    case let .invoked(transport):
      transport.send(part, promise: promise)
    }
  }

  /// Attempt to cancel the call.
  /// - Important: This *must* to be called from the `eventLoop`.
  private func _cancel(promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()

    switch self._state {
    case .idle:
      // This is weird: does it make sense to cancel before invoking it?
      promise?.fail(GRPCError.InvalidState("Call must be invoked before cancelling it"))

    case let .invoked(transport):
      transport.cancel(promise: promise)
    }
  }
}

extension Call {
  // These helpers are for our wrapping call objects (`UnaryCall`, etc.).

  /// Invokes the call and sends a single request. Sends the metadata, request and closes the
  /// request stream.
  /// - Parameters:
  ///   - request: The request to send.
  ///   - onResponsePart: A callback invoked for each response part received.
  @inlinable
  internal func invokeUnaryRequest(
    _ request: Request,
    _ onResponsePart: @escaping (ClientResponsePart<Response>) -> Void
  ) {
    if self.eventLoop.inEventLoop {
      self._invokeUnaryRequest(request: request, onResponsePart)
    } else {
      self.eventLoop.execute {
        self._invokeUnaryRequest(request: request, onResponsePart)
      }
    }
  }

  /// Invokes the call for streaming requests and sends the initial call metadata. Callers can send
  /// additional messages and end the stream by calling `send(_:promise:)`.
  /// - Parameters:
  ///   - onResponsePart: A callback invoked for each response part received.
  @inlinable
  internal func invokeStreamingRequests(
    _ onResponsePart: @escaping (ClientResponsePart<Response>) -> Void
  ) {
    if self.eventLoop.inEventLoop {
      self._invokeStreamingRequests(onResponsePart)
    } else {
      self.eventLoop.execute {
        self._invokeStreamingRequests(onResponsePart)
      }
    }
  }

  /// On-`EventLoop` implementation of `invokeUnaryRequest(request:_:)`.
  @usableFromInline
  internal func _invokeUnaryRequest(
    request: Request,
    _ onResponsePart: @escaping (ClientResponsePart<Response>) -> Void
  ) {
    self.eventLoop.assertInEventLoop()
    assert(self.type == .unary || self.type == .serverStreaming)

    self._invoke(onResponsePart)
    self._send(.metadata(self.options.customMetadata), promise: nil)
    self._send(
      .message(request, .init(compress: self.isCompressionEnabled, flush: false)),
      promise: nil
    )
    self._send(.end, promise: nil)
  }

  /// On-`EventLoop` implementation of `invokeStreamingRequests(_:)`.
  @usableFromInline
  internal func _invokeStreamingRequests(
    _ onResponsePart: @escaping (ClientResponsePart<Response>) -> Void
  ) {
    self.eventLoop.assertInEventLoop()
    assert(self.type == .clientStreaming || self.type == .bidirectionalStreaming)

    self._invoke(onResponsePart)
    self._send(.metadata(self.options.customMetadata), promise: nil)
  }
}
