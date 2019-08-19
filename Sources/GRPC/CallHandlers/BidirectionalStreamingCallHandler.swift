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
import SwiftProtobuf
import NIO
import NIOHTTP1
import Logging

/// Handles bidirectional streaming calls. Forwards incoming messages and end-of-stream events to the observer block.
///
/// - The observer block is implemented by the framework user and calls `context.sendResponse` as needed.
///   If the framework user wants to return a call error (e.g. in case of authentication failure),
///   they can fail the observer block future.
/// - To close the call and send the status, complete `context.statusPromise`.
public class BidirectionalStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias Context = StreamingResponseCallContext<ResponseMessage>
  public typealias EventObserver = (StreamEvent<RequestMessage>) -> Void
  public typealias EventObserverFactory = (Context) -> EventLoopFuture<EventObserver>

  private var observerState: ClientStreamingHandlerObserverState<EventObserverFactory, EventObserver> {
    willSet(newState) {
      self.logger.info("observerState changed from \(self.observerState) to \(newState)")
    }
  }
  private var callContext: Context?

  // We ask for a future of type `EventObserver` to allow the framework user to e.g. asynchronously authenticate a call.
  // If authentication fails, they can simply fail the observer future, which causes the call to be terminated.
  public init(callHandlerContext: CallHandlerContext, eventObserverFactory: @escaping (StreamingResponseCallContext<ResponseMessage>) -> EventLoopFuture<EventObserver>) {
    // Delay the creation of the event observer until `handlerAdded(context:)`, otherwise it is
    // possible for the service to write into the pipeline (by fulfilling the status promise
    // of the call context outside of the observer) before it has been configured.
    self.observerState = .pendingCreation(eventObserverFactory)

    super.init(callHandlerContext: callHandlerContext)

    let context = StreamingResponseCallContextImpl<ResponseMessage>(
      channel: self.callHandlerContext.channel,
      request: self.callHandlerContext.request,
      errorDelegate: self.callHandlerContext.errorDelegate,
      logger: self.callHandlerContext.logger
    )

    self.callContext = context

    context.statusPromise.futureResult.whenComplete { _ in
      // When done, reset references to avoid retain cycles.
      self.callContext = nil
      self.observerState = .notRequired
    }
  }

  public override func handlerAdded(context: ChannelHandlerContext) {
    guard let callContext = self.callContext,
      case let .pendingCreation(factory) = self.observerState else {
      self.logger.warning("handlerAdded(context:) called but handler already has a call context")
      return
    }

    let eventObserver = factory(callContext)
    self.observerState = .created(eventObserver)

    // Terminate the call if the future providing an observer fails.
    // This is being done _after_ we have been added as a handler to ensure that the `GRPCServerCodec` required to
    // translate our outgoing `GRPCServerResponsePart<ResponseMessage>` message is already present on the channel.
    // Otherwise, our `OutboundOut` type would not match the `OutboundIn` type of the next handler on the channel.
    eventObserver.cascadeFailure(to: callContext.statusPromise)
  }

  public override func processMessage(_ message: RequestMessage) {
    guard case .created(let eventObserver) = self.observerState else {
      self.logger.warning("expecting observerState to be .created but was \(self.observerState), ignoring message \(message)")
      return
    }
    eventObserver.whenSuccess { observer in
      observer(.message(message))
    }
  }

  public override func endOfStreamReceived() throws {
    guard case .created(let eventObserver) = self.observerState else {
      self.logger.warning("expecting observerState to be .created but was \(self.observerState), ignoring end-of-stream call")
      return
    }
    eventObserver.whenSuccess { observer in
      observer(.end)
    }
  }

  override func sendErrorStatus(_ status: GRPCStatus) {
    self.callContext?.statusPromise.fail(status)
  }
}
