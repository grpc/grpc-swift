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

import Foundation
import GRPC
import Logging
import NIOCore
import NIOPosix

/// Server setup for asynchronous requests.
final class AsyncQPSServerImpl: AsyncQPSServer {
  private let logger = Logger(label: "AsyncQPSServerImpl")

  private let eventLoopGroup: MultiThreadedEventLoopGroup
  private let server: Server
  private let threadCount: Int

  private var statsPeriodStart: DispatchTime
  private var cpuStatsPeriodStart: CPUTime

  var serverInfo: ServerInfo {
    let port = self.server.channel.localAddress?.port ?? 0
    return ServerInfo(threadCount: self.threadCount, port: port)
  }

  /// Initialisation.
  /// - parameters:
  ///     - config: Description of the type of server required.
  init(config: Grpc_Testing_ServerConfig) async throws {
    // Setup threads as requested.
    let threadCount = config.asyncServerThreads > 0
      ? Int(config.asyncServerThreads)
      : System.coreCount
    self.threadCount = threadCount
    self.logger.info("Sizing AsyncQPSServerImpl", metadata: ["threads": "\(threadCount)"])
    self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)

    // Start stats gathering.
    self.statsPeriodStart = grpcTimeNow()
    self.cpuStatsPeriodStart = getResourceUsage()

    let workerService = AsyncBenchmarkServiceImpl()

    // Start the server
    self.server = try await Server.insecure(group: self.eventLoopGroup)
      .withServiceProviders([workerService])
      .withLogger(self.logger)
      .bind(host: "localhost", port: Int(config.port))
      .get()
  }

  /// Send the status of the current test
  /// - parameters:
  ///     - reset: Indicates if the stats collection should be reset after publication or not.
  ///     - responseStream: the response stream to which the status should be sent.
  func sendStatus(
    reset: Bool,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ServerStatus>
  ) async throws {
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
    try await responseStream.send(result)
    if reset {
      self.statsPeriodStart = currentTime
      self.cpuStatsPeriodStart = currentResourceUsage
    }
  }

  /// Shut down the service.
  func shutdown() async throws {
    do {
      try await self.server.initiateGracefulShutdown().get()
    } catch {
      self.logger.error("Error closing server", metadata: ["error": "\(error)"])
      // May as well plough on anyway -
      // we will hopefully sort outselves out shutting down the eventloops
    }
    try await self.eventLoopGroup.shutdownGracefully()
  }
}
