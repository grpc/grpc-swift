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
///                                                          │ write(_:promise) /
///                                                          │ cancel(promise:)
/// ┌────────────────────────────────────────────────────────▼──────────┐
/// │                         InterceptorPipeline            ╎          │
/// │                                                        ╎          │
/// │ ┌──────────────────────────────────────────────────────▼────────┐ │
/// │ │     Tail Interceptor (hands response parts to a callback)     │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │          ╎                                             ╎          │
/// │          ╎              (More interceptors)            ╎          │
/// │          ╎                                             ╎          │
/// │ ┌────────┴─────────────────────────────────────────────▼────────┐ │
/// │ │                          Interceptor 2                        │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │ ┌────────┴─────────────────────────────────────────────▼────────┐ │
/// │ │                          Interceptor 1                        │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │ ┌────────┴─────────────────────────────────────────────▼────────┐ │
/// │ │          Head Interceptor (interacts with transport)          │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │  read(_:)╎                                             │          │
/// └──────────▲─────────────────────────────────────────────┼──────────┘
///    read(_:)│                                             │ write(_:promise:) /
///            │                                             │ cancel(promise:)
/// ┌──────────┴─────────────────────────────────────────────▼──────────┐
/// │                           ClientTransport                         │
/// │                       (a NIO.ChannelHandler)                      │
/// ```
internal final class ClientInterceptorPipeline<Request, Response> {
  /// A logger.
  internal let logger: Logger

  /// The `EventLoop` this RPC is being executed on.
  internal let eventLoop: EventLoop

  /// The contexts associated with the interceptors stored in this pipeline. Context will be removed
  /// once the RPC has completed.
  private var contexts: [ClientInterceptorContext<Request, Response>]

  /// Returns the context for the given index, if one exists.
  /// - Parameter index: The index of the `ClientInterceptorContext` to return.
  /// - Returns: The `ClientInterceptorContext` or `nil` if one does not exist for the given index.
  internal func context(atIndex index: Int) -> ClientInterceptorContext<Request, Response>? {
    return self.contexts[checked: index]
  }

  /// The context closest to the `NIO.Channel`, i.e. where inbound events originate. This will be
  /// `nil` once the RPC has completed.
  private var head: ClientInterceptorContext<Request, Response>? {
    return self.contexts.first
  }

  /// The context closest to the application, i.e. where outbound events originate. This will be
  /// `nil` once the RPC has completed.
  private var tail: ClientInterceptorContext<Request, Response>? {
    return self.contexts.last
  }

  internal init() {
    fatalError("Not yet implemented.")
  }

  /// Emit a response part message into the interceptor pipeline.
  ///
  /// This should be called by the transport layer when receiving a response part from the server.
  ///
  /// - Parameter part: The part to emit into the pipeline.
  /// - Important: This *must* to be called from the `eventLoop`.
  internal func read(_ part: ClientResponsePart<Response>) {
    self.eventLoop.assertInEventLoop()
    self.head?.invokeRead(part)
  }

  /// Writes a request message into the interceptor pipeline.
  ///
  /// This should be called by the call object to send requests parts to the transport.
  ///
  /// - Parameters:
  ///   - part: The request part to write.
  ///   - promise: A promise to complete when the request part has been successfully written.
  /// - Important: This *must* to be called from the `eventLoop`.
  internal func write(_ part: ClientRequestPart<Request>, promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()

    if let tail = self.tail {
      tail.invokeWrite(part, promise: promise)
    } else {
      promise?.fail(GRPCStatus(code: .unavailable, message: "The RPC has already completed"))
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

    if let tail = self.tail {
      tail.invokeCancel(promise: promise)
    } else {
      promise?.fail(GRPCStatus(code: .unavailable, message: "The RPC has already completed"))
    }
  }
}
