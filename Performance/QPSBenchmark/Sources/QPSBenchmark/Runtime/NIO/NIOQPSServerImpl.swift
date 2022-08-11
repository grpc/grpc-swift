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
import NIOPosix

/// Server setup for asynchronous requests (using EventLoopFutures).
final class NIOQPSServerImpl: NIOQPSServer {
  private let eventLoopGroup: MultiThreadedEventLoopGroup
  private let server: EventLoopFuture<Server>
  private let threadCount: Int

  private var statsPeriodStart: DispatchTime
  private var cpuStatsPeriodStart: CPUTime

  private let logger = Logger(label: "AsyncQPSServer")

  /// Initialisation.
  /// - parameters:
  ///     - config: Description of the type of server required.
  ///     - whenBound: Called when the server has successful bound to a port.
  init(config: Grpc_Testing_ServerConfig, whenBound: @escaping (ServerInfo) -> Void) {
    // Setup threads as requested.
    let threadCount = config.asyncServerThreads > 0
      ? Int(config.asyncServerThreads)
      : System.coreCount
    self.threadCount = threadCount
    self.logger.info("Sizing AsyncQPSServer", metadata: ["threads": "\(threadCount)"])
    self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)

    // Start stats gathering.
    self.statsPeriodStart = grpcTimeNow()
    self.cpuStatsPeriodStart = getResourceUsage()

    let workerService = NIOBenchmarkServiceImpl()

    // Start the server.
    // TODO: Support TLS if requested.
    self.server = Server.insecure(group: self.eventLoopGroup)
      .withServiceProviders([workerService])
      .withLogger(self.logger)
      .bind(host: "localhost", port: Int(config.port))

    self.server.whenSuccess { server in
      let port = server.channel.localAddress?.port ?? 0
      whenBound(ServerInfo(threadCount: threadCount, port: port))
    }
  }

  /// Send the status of the current test
  /// - parameters:
  ///     - reset: Indicates if the stats collection should be reset after publication or not.
  ///     - context: Context to describe where to send the status to.
  func sendStatus(reset: Bool, context: StreamingResponseCallContext<Grpc_Testing_ServerStatus>) {
    let currentTime = grpcTimeNow()
    let currentResourceUsage = getResourceUsage()
    var result = Grpc_Testing_ServerStatus()
    result.stats.timeElapsed = (currentTime - self.statsPeriodStart).asSeconds()
    result.stats.timeSystem = currentResourceUsage.systemTime - self.cpuStatsPeriodStart
      .systemTime
    result.stats.timeUser = currentResourceUsage.userTime - self.cpuStatsPeriodStart.userTime
    result.stats.totalCpuTime = 0
    result.stats.idleCpuTime = 0
    result.stats.cqPollCount = 0
    self.logger.info("Sending server status")
    _ = context.sendResponse(result)
    if reset {
      self.statsPeriodStart = currentTime
      self.cpuStatsPeriodStart = currentResourceUsage
    }
  }

  /// Shutdown the service.
  /// - parameters:
  ///     - callbackLoop: Which eventloop should be called back on completion.
  /// - returns: A future on the `callbackLoop` which will succeed on completion of shutdown.
  func shutdown(callbackLoop: EventLoop) -> EventLoopFuture<Void> {
    return self.server.flatMap { server in
      server.close()
    }.recover { error in
      self.logger.error("Error closing server", metadata: ["error": "\(error)"])
      // May as well plough on anyway -
      // we will hopefully sort outselves out shutting down the eventloops
      return ()
    }.hop(to: callbackLoop).flatMap { _ in
      let promise: EventLoopPromise<Void> = callbackLoop.makePromise()
      self.eventLoopGroup.shutdownGracefully { error in
        if let error = error {
          promise.fail(error)
        } else {
          promise.succeed(())
        }
      }
      return promise.futureResult
    }
  }
}
