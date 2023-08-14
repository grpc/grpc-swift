/*
 * Copyright 2022, gRPC Authors All rights reserved.
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

import Atomics
import Foundation
import GRPC
import Logging
import NIOCore

/// Makes streaming requests and listens to responses ping-pong style.
/// Iterations can be limited by config.
/// Class is marked as `@unchecked Sendable` because `ManagedAtomic<Bool>` doesn't conform
/// to `Sendable`, but we know it's safe.
final class AsyncPingPongRequestMaker: AsyncRequestMaker, @unchecked Sendable {
  private let client: Grpc_Testing_BenchmarkServiceAsyncClient
  private let requestMessage: Grpc_Testing_SimpleRequest
  private let logger: Logger
  private let stats: StatsWithLock

  /// If greater than zero gives a limit to how many messages are exchanged before termination.
  private let messagesPerStream: Int
  /// Stops more requests being made after stop is requested.
  private let stopRequested = ManagedAtomic<Bool>(false)

  /// Initialiser to gather requirements.
  /// - Parameters:
  ///    - config: config from the driver describing what to do.
  ///    - client: client interface to the server.
  ///    - requestMessage: Pre-made request message to use possibly repeatedly.
  ///    - logger: Where to log useful diagnostics.
  ///    - stats: Where to record statistics on latency.
  init(
    config: Grpc_Testing_ClientConfig,
    client: Grpc_Testing_BenchmarkServiceAsyncClient,
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
  func makeRequest() async throws {
    var startTime = grpcTimeNow()
    var messagesSent = 0

    let streamingCall = self.client.makeStreamingCallCall()
    var responseStream = streamingCall.responseStream.makeAsyncIterator()
    while !self.stopRequested.load(ordering: .relaxed),
          self.messagesPerStream == 0 || messagesSent < self.messagesPerStream {
      try await streamingCall.requestStream.send(self.requestMessage)
      _ = try await responseStream.next()
      let endTime = grpcTimeNow()
      self.stats.add(latency: endTime - startTime)
      messagesSent += 1
      startTime = endTime
    }
  }

  /// Request termination of the request-response sequence.
  func requestStop() {
    self.logger.info("AsyncPingPongRequestMaker stop requested")
    // Flag stop as requested - this will prevent any more requests being made.
    self.stopRequested.store(true, ordering: .relaxed)
  }
}
