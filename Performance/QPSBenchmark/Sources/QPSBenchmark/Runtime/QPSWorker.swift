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
import NIO

/// Sets up and runs a worker service which listens for instructions on what tests to run.
/// Currently doesn't understand TLS for communication with the driver.
class QPSWorker {
  private var driverPort: Int
  private var serverPort: Int?

  /// Initialise.
  /// - parameters:
  ///     - driverPort: Port to listen for instructions on.
  ///     - serverPort: Possible override for the port the testing will actually occur on - usually supplied by the driver process.
  init(driverPort: Int, serverPort: Int?) {
    self.driverPort = driverPort
    self.serverPort = serverPort
  }

  private let logger = Logger(label: "QPSWorker")

  private var eventLoopGroup: MultiThreadedEventLoopGroup?
  private var server: EventLoopFuture<Server>?
  private var workEndFuture: EventLoopFuture<Void>?

  /// Start up the server which listens for instructions from the driver.
  /// - parameters:
  ///     - onQuit: Function to call when the driver has indicated that the server should exit.
  func start(onQuit: @escaping () -> Void) {
    precondition(self.eventLoopGroup == nil)
    self.logger.info("Starting")
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.eventLoopGroup = eventLoopGroup

    let workEndPromise: EventLoopPromise<Void> = eventLoopGroup.next().makePromise()
    workEndPromise.futureResult.whenSuccess(onQuit)
    let workerService = WorkerServiceImpl(
      finishedPromise: workEndPromise,
      serverPortOverride: self.serverPort
    )

    // Start the server.
    self.logger.info("Binding to localhost", metadata: ["driverPort": "\(self.driverPort)"])
    self.server = Server.insecure(group: eventLoopGroup)
      .withServiceProviders([workerService])
      .withLogger(Logger(label: "GRPC"))
      .bind(host: "localhost", port: self.driverPort)
  }

  /// Shutdown waiting for completion.
  func syncShutdown() throws {
    precondition(self.eventLoopGroup != nil)
    self.logger.info("Stopping")
    try self.eventLoopGroup?.syncShutdownGracefully()
    self.logger.info("Stopped")
  }
}
