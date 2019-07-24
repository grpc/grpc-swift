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

/// For calls which support client streaming we need to delay the creation of the event observer
/// until the handler has been added to the pipeline.
enum ClientStreamingHandlerObserverState<Factory, Observer> {
  case pendingCreation(Factory)
  case created(EventLoopFuture<Observer>)
  case notRequired
}

/// Handles client-streaming calls. Forwards incoming messages and end-of-stream events to the observer block.
///
/// - The observer block is implemented by the framework user and fulfills `context.responsePromise` when done.
///   If the framework user wants to return a call error (e.g. in case of authentication failure),
///   they can fail the observer block future.
/// - To close the call and send the response, complete `context.responsePromise`.
public class ClientStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias Context = UnaryResponseCallContext<ResponseMessage>
  public typealias EventObserver = (StreamEvent<RequestMessage>) -> Void
  public typealias EventObserverFactory = (Context) -> EventLoopFuture<EventObserver>

  private var observerState: ClientStreamingHandlerObserverState<EventObserverFactory, EventObserver>
  private var callContext: UnaryResponseCallContext<ResponseMessage>?

  // We ask for a future of type `EventObserver` to allow the framework user to e.g. asynchronously authenticate a call.
  // If authentication fails, they can simply fail the observer future, which causes the call to be terminated.
  public init(channel: Channel, request: HTTPRequestHead, errorDelegate: ServerErrorDelegate?, eventObserverFactory: @escaping EventObserverFactory) {
    // Delay the creation of the event observer until `handlerAdded(context:)`, otherwise it is
    // possible for the service to write into the pipeline (by fulfilling the response promise
    // of the call context outside of the observer) before it has been configured.
    self.observerState = .pendingCreation(eventObserverFactory)

    let callContext = UnaryResponseCallContextImpl<ResponseMessage>(channel: channel, request: request, errorDelegate: errorDelegate)
    self.callContext = callContext

    super.init(errorDelegate: errorDelegate)

    callContext.responsePromise.futureResult.whenComplete { _ in
      // When done, reset references to avoid retain cycles.
      self.callContext = nil
      self.observerState = .notRequired
    }
  }

  public override func handlerAdded(context: ChannelHandlerContext) {
    guard let callContext = self.callContext,
      case let .pendingCreation(factory) = self.observerState else {
      return
    }

    let eventObserver = factory(callContext)
    self.observerState = .created(eventObserver)

    // Terminate the call if the future providing an observer fails.
    // This is being done _after_ we have been added as a handler to ensure that the `GRPCServerCodec` required to
    // translate our outgoing `GRPCServerResponsePart<ResponseMessage>` message is already present on the channel.
    // Otherwise, our `OutboundOut` type would not match the `OutboundIn` type of the next handler on the channel.
    eventObserver.cascadeFailure(to: callContext.responsePromise)
  }

  public override func processMessage(_ message: RequestMessage) {
    guard case .created(let eventObserver) = self.observerState else { return }
    eventObserver.whenSuccess { observer in
      observer(.message(message))
    }
  }

  public override func endOfStreamReceived() throws {
    guard case .created(let eventObserver) = self.observerState else { return }
    eventObserver.whenSuccess { observer in
      observer(.end)
    }
  }

  override func sendErrorStatus(_ status: GRPCStatus) {
    self.callContext?.responsePromise.fail(status)
  }
}
