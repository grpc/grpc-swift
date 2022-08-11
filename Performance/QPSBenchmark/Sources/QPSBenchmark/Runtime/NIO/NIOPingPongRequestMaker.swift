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

import Foundation
import GRPC
import Logging
import NIOCore

/// Makes streaming requests and listens to responses ping-pong style.
/// Iterations can be limited by config.
final class NIOPingPongRequestMaker: NIORequestMaker {
  private let client: Grpc_Testing_BenchmarkServiceNIOClient
  private let requestMessage: Grpc_Testing_SimpleRequest
  private let logger: Logger
  private let stats: StatsWithLock

  /// If greater than zero gives a limit to how many messages are exchanged before termination.
  private let messagesPerStream: Int
  /// Stops more requests being made after stop is requested.
  private var stopRequested = false

  /// Initialiser to gather requirements.
  /// - Parameters:
  ///    - config: config from the driver describing what to do.
  ///    - client: client interface to the server.
  ///    - requestMessage: Pre-made request message to use possibly repeatedly.
  ///    - logger: Where to log useful diagnostics.
  ///    - stats: Where to record statistics on latency.
  init(
    config: Grpc_Testing_ClientConfig,
    client: Grpc_Testing_BenchmarkServiceNIOClient,
    requestMessage: Grpc_Testing_SimpleRequest,
    logger: Logger,
    stats: StatsWithLock
  ) {
    self.client = client
    self.requestMessage = requestMessage
    self.logger = logger
    self.stats = stats

    self.messagesPerStream = Int(config.messagesPerStream)
  }

  /// Initiate a request sequence to the server - in this case the sequence is streaming requests to the server and waiting
  /// to see responses before repeating ping-pong style.  The number of iterations can be limited by config.
  /// - returns: A future which completes when the request-response sequence is complete.
  func makeRequest() -> EventLoopFuture<GRPCStatus> {
    var startTime = grpcTimeNow()
    var messagesSent = 1
    var streamingCall: BidirectionalStreamingCall<
      Grpc_Testing_SimpleRequest,
      Grpc_Testing_SimpleResponse
    >?

    /// Handle a response from the server - potentially triggers making another request.
    /// Will execute on the event loop which deals with thread safety concerns.
    func handleResponse(response: Grpc_Testing_SimpleResponse) {
      streamingCall!.eventLoop.preconditionInEventLoop()
      let endTime = grpcTimeNow()
      self.stats.add(latency: endTime - startTime)
      if !self.stopRequested,
         self.messagesPerStream == 0 || messagesSent < self.messagesPerStream {
        messagesSent += 1
        startTime = endTime // Use end of previous request as the start of the next.
        streamingCall!.sendMessage(self.requestMessage, promise: nil)
      } else {
        streamingCall!.sendEnd(promise: nil)
      }
    }

    // Setup the call.
    streamingCall = self.client.streamingCall(handler: handleResponse)
    // Kick start with initial request
    streamingCall!.sendMessage(self.requestMessage, promise: nil)

    return streamingCall!.status
  }

  /// Request termination of the request-response sequence.
  func requestStop() {
    // Flag stop as requested - this will prevent any more requests being made.
    self.stopRequested = true
  }
}
