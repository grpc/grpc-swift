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

import GRPC
import Logging
import NIOCore

/// Implement to provide a method of making requests to a server from a client.
protocol RequestMaker {
  /// Initialiser to gather requirements.
  /// - Parameters:
  ///    - config: config from the driver describing what to do.
  ///    - client: client interface to the server.
  ///    - requestMessage: Pre-made request message to use possibly repeatedly.
  ///    - logger: Where to log useful diagnostics.
  ///    - stats: Where to record statistics on latency.
  init(
    config: Grpc_Testing_ClientConfig,
    client: Grpc_Testing_BenchmarkServiceClient,
    requestMessage: Grpc_Testing_SimpleRequest,
    logger: Logger,
    stats: StatsWithLock
  )

  /// Initiate a request sequence to the server.
  /// - returns: A future which completes when the request-response sequence is complete.
  func makeRequest() -> EventLoopFuture<GRPCStatus>

  /// Request termination of the request-response sequence.
  func requestStop()
}
