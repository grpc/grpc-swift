/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
import Logging
import NIO
import NIOHTTP1
import SwiftProtobuf

/// Handles client-streaming calls. Forwards incoming messages and end-of-stream events to the observer block.
///
/// - The observer block is implemented by the framework user and fulfills `context.responsePromise` when done.
///   If the framework user wants to return a call error (e.g. in case of authentication failure),
///   they can fail the observer block future.
/// - To close the call and send the response, complete `context.responsePromise`.
public final class ClientStreamingCallHandler<
  RequestPayload,
  ResponsePayload
>: _BaseCallHandler<RequestPayload, ResponsePayload> {
  public typealias Context = UnaryResponseCallContext<ResponsePayload>
  public typealias EventObserver = (StreamEvent<RequestPayload>) -> Void
  public typealias EventObserverFactory = (Context) -> EventLoopFuture<EventObserver>

  private var callContext: UnaryResponseCallContext<ResponsePayload>?
  private var eventObserver: EventLoopFuture<EventObserver>?
  private let eventObserverFactory: EventObserverFactory

  // We ask for a future of type `EventObserver` to allow the framework user to e.g. asynchronously authenticate a call.
  // If authentication fails, they can simply fail the observer future, which causes the call to be terminated.
  internal init<Serializer: MessageSerializer, Deserializer: MessageDeserializer>(
    serializer: Serializer,
    deserializer: Deserializer,
    callHandlerContext: CallHandlerContext,
    eventObserverFactory: @escaping EventObserverFactory
  ) where Serializer.Input == ResponsePayload, Deserializer.Output == RequestPayload {
    self.eventObserverFactory = eventObserverFactory
    super.init(
      callHandlerContext: callHandlerContext,
      codec: GRPCServerCodecHandler(serializer: serializer, deserializer: deserializer)
    )
  }

  override internal func processHead(_ head: HTTPRequestHead, context: ChannelHandlerContext) {
    let callContext = UnaryResponseCallContextImpl<ResponsePayload>(
      channel: context.channel,
      request: head,
      errorDelegate: self.errorDelegate,
      logger: self.logger
    )

    self.callContext = callContext

    let eventObserver = self.eventObserverFactory(callContext)
    eventObserver.cascadeFailure(to: callContext.responsePromise)

    self.eventObserver = eventObserver

    callContext.responsePromise.futureResult.whenComplete { _ in
      // When done, reset references to avoid retain cycles.
      self.eventObserver = nil
      self.callContext = nil
    }

    context.writeAndFlush(self.wrapOutboundOut(.headers([:])), promise: nil)
  }

  override internal func processMessage(_ message: RequestPayload) {
    guard let eventObserver = self.eventObserver else {
      self.logger.warning("eventObserver is nil; ignoring message", source: "GRPC")
      return
    }
    eventObserver.whenSuccess { observer in
      observer(.message(message))
    }
  }

  override internal func endOfStreamReceived() throws {
    guard let eventObserver = self.eventObserver else {
      self.logger.warning("eventObserver is nil; ignoring end-of-stream", source: "GRPC")
      return
    }
    eventObserver.whenSuccess { observer in
      observer(.end)
    }
  }

  override internal func sendErrorStatusAndMetadata(_ statusAndMetadata: GRPCStatusAndMetadata) {
    if let metadata = statusAndMetadata.metadata {
      self.callContext?.trailingMetadata.add(contentsOf: metadata)
    }
    self.callContext?.responsePromise.fail(statusAndMetadata.status)
  }
}
