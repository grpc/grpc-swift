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

/// A pipeline for intercepting client request and response streams.
///
/// The interceptor pipeline lies between the call object (`UnaryCall`, `ClientStreamingCall`, etc.)
/// and the transport used to send and receive messages from the server (a `NIO.Channel`). It holds
/// a collection of interceptors which may be used to observe or alter messages as the travel
/// through the pipeline.
///
/// ```
/// ┌───────────────────────────────────────────────────────────────────┐
/// │                                Call                               │
/// └────────────────────────────────────────────────────────┬──────────┘
///                                                          │ send(_:promise) /
///                                                          │ cancel(promise:)
/// ┌────────────────────────────────────────────────────────▼──────────┐
/// │                         InterceptorPipeline            ╎          │
/// │                                                        ╎          │
/// │ ┌──────────────────────────────────────────────────────▼────────┐ │
/// │ │     Tail Interceptor (hands response parts to a callback)     │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │ ┌────────┴─────────────────────────────────────────────▼────────┐ │
/// │ │                          Interceptor 1                        │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │ ┌────────┴─────────────────────────────────────────────▼────────┐ │
/// │ │                          Interceptor 2                        │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │          ╎                                             ╎          │
/// │          ╎              (More interceptors)            ╎          │
/// │          ╎                                             ╎          │
/// │ ┌────────┴─────────────────────────────────────────────▼────────┐ │
/// │ │          Head Interceptor (interacts with transport)          │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │          ╎ receive(_:)                                 │          │
/// └──────────▲─────────────────────────────────────────────┼──────────┘
///            │ receive(_:)                                 │ send(_:promise:) /
///            │                                             │ cancel(promise:)
/// ┌──────────┴─────────────────────────────────────────────▼──────────┐
/// │                           ClientTransport                         │
/// │                       (a NIO.ChannelHandler)                      │
/// ```
@usableFromInline
internal final class ClientInterceptorPipeline<Request, Response> {
  /// A logger.
  internal var logger: Logger {
    return self.details.options.logger
  }

  /// The `EventLoop` this RPC is being executed on.
  @usableFromInline
  internal let eventLoop: EventLoop

  /// The details of the call.
  internal let details: CallDetails

  /// A task for closing the RPC in case of a timeout.
  private var scheduledClose: Scheduled<Void>?

  /// The contexts associated with the interceptors stored in this pipeline. Context will be removed
  /// once the RPC has completed. Contexts are ordered from outbound to inbound, that is, the tail
  /// is first and the head is last.
  private var contexts: [ClientInterceptorContext<Request, Response>]?

  /// Returns the next context in the outbound direction for the context at the given index, if one
  /// exists.
  /// - Parameter index: The index of the `ClientInterceptorContext` which is requesting the next
  ///   outbound context.
  /// - Returns: The `ClientInterceptorContext` or `nil` if one does not exist.
  internal func nextOutboundContext(
    forIndex index: Int
  ) -> ClientInterceptorContext<Request, Response>? {
    return self.context(atIndex: index + 1)
  }

  /// Returns the next context in the inbound direction for the context at the given index, if one
  /// exists.
  /// - Parameter index: The index of the `ClientInterceptorContext` which is requesting the next
  ///   inbound context.
  /// - Returns: The `ClientInterceptorContext` or `nil` if one does not exist.
  internal func nextInboundContext(
    forIndex index: Int
  ) -> ClientInterceptorContext<Request, Response>? {
    return self.context(atIndex: index - 1)
  }

  /// Returns the context for the given index, if one exists.
  /// - Parameter index: The index of the `ClientInterceptorContext` to return.
  /// - Returns: The `ClientInterceptorContext` or `nil` if one does not exist for the given index.
  private func context(atIndex index: Int) -> ClientInterceptorContext<Request, Response>? {
    return self.contexts?[checked: index]
  }

  /// The context closest to the `NIO.Channel`, i.e. where inbound events originate. This will be
  /// `nil` once the RPC has completed.
  @usableFromInline
  internal var _head: ClientInterceptorContext<Request, Response>? {
    return self.contexts?.last
  }

  /// The context closest to the application, i.e. where outbound events originate. This will be
  /// `nil` once the RPC has completed.
  @usableFromInline
  internal var _tail: ClientInterceptorContext<Request, Response>? {
    return self.contexts?.first
  }

  internal init(
    eventLoop: EventLoop,
    details: CallDetails,
    interceptors: [ClientInterceptor<Request, Response>],
    errorDelegate: ClientErrorDelegate?,
    onCancel: @escaping (EventLoopPromise<Void>?) -> Void,
    onRequestPart: @escaping (GRPCClientRequestPart<Request>, EventLoopPromise<Void>?) -> Void,
    onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) {
    self.eventLoop = eventLoop
    self.details = details

    // We know we'll have at least a head and a tail as well as any user provided interceptors.
    var contexts: [ClientInterceptorContext<Request, Response>] = []
    contexts.reserveCapacity(interceptors.count + 2)

    // Start with the tail.
    contexts.append(
      ClientInterceptorContext(
        for: .tail(for: self, errorDelegate: errorDelegate, onResponsePart),
        atIndex: contexts.count,
        in: self
      )
    )

    // Now the user interceptors.
    for interceptor in interceptors {
      contexts.append(
        ClientInterceptorContext(
          for: .userProvided(interceptor),
          atIndex: contexts.count,
          in: self
        )
      )
    }

    // Finally, the head.
    contexts.append(
      ClientInterceptorContext(
        for: .head(onCancel: onCancel, onRequestPart: onRequestPart),
        atIndex: contexts.count,
        in: self
      )
    )

    self.contexts = contexts
    self.setupDeadline()
  }

  /// Emit a response part message into the interceptor pipeline.
  ///
  /// This should be called by the transport layer when receiving a response part from the server.
  ///
  /// - Parameter part: The part to emit into the pipeline.
  /// - Important: This *must* to be called from the `eventLoop`.
  internal func receive(_ part: GRPCClientResponsePart<Response>) {
    self.eventLoop.assertInEventLoop()
    self._head?.invokeReceive(part)
  }

  /// Writes a request message into the interceptor pipeline.
  ///
  /// This should be called by the call object to send requests parts to the transport.
  ///
  /// - Parameters:
  ///   - part: The request part to write.
  ///   - promise: A promise to complete when the request part has been successfully written.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func send(_ part: GRPCClientRequestPart<Request>, promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()

    if let tail = self._tail {
      tail.invokeSend(part, promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  /// Send a request to cancel the RPC through the interceptor pipeline.
  ///
  /// This should be called by the call object when attempting to cancel the RPC.
  ///
  /// - Parameter promise: A promise to complete when the cancellation request has been handled.
  /// - Important: This *must* to be called from the `eventLoop`.
  internal func cancel(promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()

    if let tail = self._tail {
      tail.invokeCancel(promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }
}

// MARK: - Lifecycle

extension ClientInterceptorPipeline {
  /// Closes the pipeline. This should be called once, by the tail interceptor, to indicate that
  /// the RPC has completed.
  /// - Important: This *must* to be called from the `eventLoop`.
  internal func close() {
    self.eventLoop.assertInEventLoop()

    // Grab the head, we'll use it to cancel the transport. This is most likely already closed,
    // but there's nothing to stop an interceptor from emitting its own error and leaving the
    // transport open.
    let head = self._head
    self.contexts = nil

    // Cancel the timeout.
    self.scheduledClose?.cancel()
    self.scheduledClose = nil

    // Cancel the transport.
    head?.invokeCancel(promise: nil)
  }

  /// Sets up a deadline for the pipeline.
  private func setupDeadline() {
    if self.eventLoop.inEventLoop {
      self._setupDeadline()
    } else {
      self.eventLoop.execute {
        self._setupDeadline()
      }
    }
  }

  /// Sets up a deadline for the pipeline.
  /// - Important: This *must* to be called from the `eventLoop`.
  private func _setupDeadline() {
    self.eventLoop.assertInEventLoop()

    let timeLimit = self.details.options.timeLimit
    let deadline = timeLimit.makeDeadline()

    // There's no point scheduling this.
    if deadline == .distantFuture {
      return
    }

    self.scheduledClose = self.eventLoop.scheduleTask(deadline: deadline) {
      // When the error hits the tail we'll call 'close()', this will cancel the transport if
      // necessary.
      self.receive(.error(GRPCError.RPCTimedOut(timeLimit)))
    }
  }
}
