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

import GRPC
import NIOCore

/// Protocol which async clients must implement.
protocol AsyncQPSClient {
  /// Start the execution of the client.
  func startClient()

  /// Send the status of the current test
  /// - parameters:
  ///     - reset: Indicates if the stats collection should be reset after publication or not.
  ///     - responseStream: the response stream to write the response to.
  func sendStatus(
    reset: Bool,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ClientStatus>
  ) async throws

  /// Shut down the client.
  func shutdown() async throws
}
