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
import NIO

/// Interface server types must implement.
protocol QPSServer {
  /// Send the status of the current test
  /// - parameters:
  ///     - reset: Indicates if the stats collection should be reset after publication or not.
  ///     - context: Context to describe where to send the status to.
  func sendStatus(reset: Bool, context: StreamingResponseCallContext<Grpc_Testing_ServerStatus>)

  /// Shutdown the service.
  /// - parameters:
  ///     - callbackLoop: Which eventloop should be called back on completion.
  /// - returns: A future on the `callbackLoop` which will succeed on completion of shutdown.
  func shutdown(callbackLoop: EventLoop) -> EventLoopFuture<Void>
}
