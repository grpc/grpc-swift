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
import NIO

/// Makes streaming requests and listens to responses ping-pong style.
/// Iterations can be limited by config.
final class AsyncPingPongRequestMaker: RequestMaker {
  private let client: Grpc_Testing_BenchmarkServiceClient
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
  init(config: Grpc_Testing_ClientConfig,
       client: Grpc_Testing_BenchmarkServiceClient,
       requestMessage: Grpc_Testing_SimpleRequest,
       logger: Logger,
       stats: StatsWithLock) {
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
    func handleResponse(response: Grpc_Testing_SimpleResponse) {
      let endTime = grpcTimeNow()
      self.stats.add(latency: endTime - startTime)
      if !self.stopRequested,
        self.messagesPerStream == 0 || messagesSent < self.messagesPerStream {
        messagesSent += 1
        startTime = endTime // Use end of previous request as the start of the next.
        _ = streamingCall!.sendMessage(self.requestMessage)
      } else {
        streamingCall!.sendEnd(promise: nil)
      }
    }

    // Setup the call.
    streamingCall = self.client.streamingCall(handler: handleResponse)
    // Kick start with initial request
    _ = streamingCall!.sendMessage(self.requestMessage)

    return streamingCall!.status
  }

  /// Request termination of the request-response sequence.
  func requestStop() {
    // Flag stop as requested - this will prevent any more requests being made.
    self.stopRequested = true
  }
}

/*
 /// Client to make a series of asynchronous streaming calls.
 final class AsyncPingPongQPSClient: QPSClient {
     private let asyncClient: AsyncQPSClientHelper<ChannelRepeater>

     /// Initialise a client to send streaming requests and receive responses.
     /// - parameters:
     ///      - config: Config from the driver specifying how the client should behave.
     init(config: Grpc_Testing_ClientConfig) throws {
         self.asyncClient = try AsyncQPSClientHelper<ChannelRepeater>(config: config)
     }

     func sendStatus(reset: Bool, context: StreamingResponseCallContext<Grpc_Testing_ClientStatus>) {
         return self.asyncClient.sendStatus(reset: reset, context: context)
     }

     func shutdown(callbackLoop: EventLoop) -> EventLoopFuture<Void> {
         return self.asyncClient.shutdown(callbackLoop: callbackLoop)
     }

     private final class ChannelRepeater: BenchmarkChannelHandler {
         private let connection: ClientConnection
         private let client: Grpc_Testing_BenchmarkServiceClient
         private let requestMessage: Grpc_Testing_SimpleRequest
         private let logger = Logger(label: "ChannelRepeater")
         private let maxPermittedOutstandingRequests: Int    // TODO:  Is this needed?

         private var stats: StatsWithLock

         /// Has a stop been requested - if it has don't submit any more
         /// requests and when all existing requests are complete signal
         /// using `stopComplete`
         private var stopRequested = false
         /// Succeeds after a stop has been requested and all outstanding requests have completed.
         private var stopComplete: EventLoopPromise<Void>
         private var numberOfOutstandingRequests = 0

         // Extra
         private let messagesPerStream: Int

         init(target: HostAndPort,
              requestMessage: Grpc_Testing_SimpleRequest,
              config: Grpc_Testing_ClientConfig,
              eventLoopGroup: EventLoopGroup) {
             // TODO: Support TLS if requested.
             self.connection = ClientConnection.insecure(group: eventLoopGroup)
               .connect(host: target.host, port: target.port)
             self.client = Grpc_Testing_BenchmarkServiceClient(channel: self.connection)
             self.requestMessage = requestMessage
             self.maxPermittedOutstandingRequests = Int(config.outstandingRpcsPerChannel)
             self.stopComplete = self.connection.eventLoop.makePromise()
             self.stats = StatsWithLock()

             // Extra loops
             self.messagesPerStream = Int(config.messagesPerStream)

         }

         /// Launch as many requests as allowed on the channel.
         /// This must be called from the connection eventLoop.
         private func launchRequests() {
           precondition(self.connection.eventLoop.inEventLoop)
           while self.canMakeRequest {
             self.makeRequestAndRepeat()
           }
         }

         /// Returns if it is permissible to make another request - ie we've not been asked to stop, and we're not at the limit of outstanding requests.
         private var canMakeRequest: Bool {
           return !self.stopRequested
             && self.numberOfOutstandingRequests < self.maxPermittedOutstandingRequests
         }

         /// If there is spare permitted capacity make a request and repeat when it is done.
         private func makeRequestAndRepeat() {
           // Check for capacity.
           if !self.canMakeRequest {
             return
           }
           let startTime = grpcTimeNow()
             var messagesSent = 1
           self.numberOfOutstandingRequests += 1

            var streamingCall: BidirectionalStreamingCall<Grpc_Testing_SimpleRequest, Grpc_Testing_SimpleResponse>?
            streamingCall = self.client.streamingCall(handler: { _ in
             // TODO:  Number of allowed repeats.
             let endTime = grpcTimeNow()
             self.recordLatency(endTime - startTime)
             if !self.stopRequested && (self.messagesPerStream == 0 || messagesSent < self.messagesPerStream) {
                 messagesSent += 1
                 _ = streamingCall!.sendMessage(self.requestMessage)
             } else {
                 streamingCall!.sendEnd(promise: nil)
             }
            })
                 // callOptions: CallOptions? = nil,
                 // handler: @escaping (Grpc_Testing_SimpleResponse) -> Void
               // ) -> BidirectionalStreamingCall<Grpc_Testing_SimpleRequest, Grpc_Testing_SimpleResponse>
           // let result = self.client.unaryCall(self.requestMessage)

             // streamingCall:
             _ = streamingCall!.sendMessage(self.requestMessage)

             // This triggers when the stream ends - we may have a message limit.
             streamingCall!.status.whenSuccess { status in
                 self.requestCompleted(status: status, startTime: startTime)
             }

         }

         /// Call when a request has completed.
         /// Records stats and attempts to make more requests if there is available capacity.
         private func requestCompleted(status: GRPCStatus, startTime: DispatchTime) {
           precondition(self.connection.eventLoop.inEventLoop)
           self.numberOfOutstandingRequests -= 1
           if status.isOk {
             let endTime = grpcTimeNow()
             self.recordLatency(endTime - startTime)
           } else {
             self.logger.error(
               "Bad status from unary request",
               metadata: ["status": "\(status)"]
             )
           }
           if self.stopRequested, self.numberOfOutstandingRequests == 0 {
             self.stopIsComplete()
           } else {
             // Try scheduling another request.
             self.makeRequestAndRepeat()
           }
         }

         private func recordLatency(_ latency: Nanoseconds) {
           self.stats.add(latency: Double(latency.value))
         }

         /// Get stats for sending to the driver.
         /// - parameters:
         ///     - reset: Should the stats reset after copying.
         /// - returns: The statistics for this channel.
         func getStats(reset: Bool) -> Stats {
           return self.stats.copyData(reset: reset)
         }

         /// Start sending requests to the server.
         func start() {
           if self.connection.eventLoop.inEventLoop {
             self.launchRequests()
           } else {
             self.connection.eventLoop.execute {
               self.launchRequests()
             }
           }
         }

         private func stopIsComplete() {
           assert(self.stopRequested)
           assert(self.numberOfOutstandingRequests == 0)
           // Close the connection then signal done.
           self.connection.close().cascade(to: self.stopComplete)
         }

         /// Stop sending requests to the server.
         /// - returns: A future which can be waited on to signal when all activity has ceased.
         func stop() -> EventLoopFuture<Void> {
           self.connection.eventLoop.execute {
             self.stopRequested = true
             if self.numberOfOutstandingRequests == 0 {
               self.stopIsComplete()
             }
           }
           return self.stopComplete.futureResult
         }
     }

 }
 */
