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

/// Handles server-streaming calls. Calls the observer block with the request message.
///
/// - The observer block is implemented by the framework user and calls `context.sendResponse` as needed.
/// - To close the call and send the status, complete the status future returned by the observer block.
public final class ServerStreamingCallHandler<
  RequestPayload: GRPCPayload,
  ResponsePayload: GRPCPayload
>: _BaseCallHandler<RequestPayload, ResponsePayload> {
  public typealias EventObserver = (RequestPayload) -> EventLoopFuture<GRPCStatus>

  private var eventObserver: EventObserver?
  private var callContext: StreamingResponseCallContext<ResponsePayload>?
  private let eventObserverFactory: (StreamingResponseCallContext<ResponsePayload>) -> EventObserver

  public init(
    callHandlerContext: CallHandlerContext,
    eventObserverFactory: @escaping (StreamingResponseCallContext<ResponsePayload>) -> EventObserver
  ) {
    // Delay the creation of the event observer until we actually get a request head, otherwise it
    // would be possible for the observer to write into the pipeline (by completing the status
    // promise) before the pipeline is configured.
    self.eventObserverFactory = eventObserverFactory
    super.init(callHandlerContext: callHandlerContext)
  }

  override internal func processHead(_ head: HTTPRequestHead, context: ChannelHandlerContext) {
    let callContext = StreamingResponseCallContextImpl<ResponsePayload>(
      channel: context.channel,
      request: head,
      errorDelegate: self.callHandlerContext.errorDelegate,
      logger: self.callHandlerContext.logger
    )

    self.callContext = callContext
    self.eventObserver = eventObserverFactory(callContext)
    callContext.statusPromise.futureResult.whenComplete { _ in
      // When done, reset references to avoid retain cycles.
      self.eventObserver = nil
      self.callContext = nil
    }

    context.writeAndFlush(self.wrapOutboundOut(.headers([:])), promise: nil)
  }

  override internal func processMessage(_ message: RequestPayload) throws {
    guard let eventObserver = self.eventObserver,
      let callContext = self.callContext else {
        self.logger.error("processMessage(_:) called before the call started or after the call completed")
        throw GRPCError.StreamCardinalityViolation.request.captureContext()
    }

    let resultFuture = eventObserver(message)
    resultFuture
      // Fulfil the status promise with whatever status the framework user has provided.
      .cascade(to: callContext.statusPromise)
    self.eventObserver = nil
  }

  override internal func endOfStreamReceived() throws {
    if self.eventObserver != nil {
      throw GRPCError.StreamCardinalityViolation.request.captureContext()
    }
  }

  override internal func sendErrorStatus(_ status: GRPCStatus) {
    self.callContext?.statusPromise.fail(status)
  }
}
