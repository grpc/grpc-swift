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

/// Handles server-streaming calls. Calls the observer block with the request message.
///
/// - The observer block is implemented by the framework user and calls `context.sendResponse` as needed.
/// - To close the call and send the status, complete the status future returned by the observer block.
public class ServerStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> EventLoopFuture<GRPCStatus>
  private var eventObserver: EventObserver?

  private var callContext: StreamingResponseCallContext<ResponseMessage>?

  public init(channel: Channel, request: HTTPRequestHead, errorDelegate: ServerErrorDelegate?, eventObserverFactory: (StreamingResponseCallContext<ResponseMessage>) -> EventObserver) {
    super.init(errorDelegate: errorDelegate)
    let callContext = StreamingResponseCallContextImpl<ResponseMessage>(channel: channel, request: request, errorDelegate: errorDelegate)
    self.callContext = callContext
    self.eventObserver = eventObserverFactory(callContext)
    callContext.statusPromise.futureResult.whenComplete { _ in
      // When done, reset references to avoid retain cycles.
      self.eventObserver = nil
      self.callContext = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) throws {
    guard let eventObserver = self.eventObserver,
      let callContext = self.callContext else {
        throw GRPCError.server(.tooManyRequests)
    }

    let resultFuture = eventObserver(message)
    resultFuture
      // Fulfill the status promise with whatever status the framework user has provided.
      .cascade(to: callContext.statusPromise)
    self.eventObserver = nil
  }

  public override func endOfStreamReceived() throws {
    if self.eventObserver != nil {
      throw GRPCError.server(.noRequestsButOneExpected)
    }
  }

  override func sendErrorStatus(_ status: GRPCStatus) {
    self.callContext?.statusPromise.fail(status)
  }
}
