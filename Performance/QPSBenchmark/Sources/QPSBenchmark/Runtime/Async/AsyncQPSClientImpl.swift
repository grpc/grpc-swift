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
import BenchmarkUtils
import Foundation
import GRPC
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix

/// Client to make a series of asynchronous calls.
final class AsyncQPSClientImpl<RequestMakerType: AsyncRequestMaker>: AsyncQPSClient {
  private let logger = Logger(label: "AsyncQPSClientImpl")

  private let eventLoopGroup: MultiThreadedEventLoopGroup
  private let threadCount: Int
  private let channelRepeaters: [ChannelRepeater]

  private var statsPeriodStart: DispatchTime
  private var cpuStatsPeriodStart: CPUTime

  /// Initialise a client to send requests.
  /// - parameters:
  ///      - config: Config from the driver specifying how the client should behave.
  init(config: Grpc_Testing_ClientConfig) throws {
    // Setup threads
    let threadCount = config.threadsToUse()
    self.threadCount = threadCount
    self.logger.info("Sizing AsyncQPSClientImpl", metadata: ["threads": "\(threadCount)"])
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)
    self.eventLoopGroup = eventLoopGroup

    // Parse possible invalid targets before code with side effects.
    let serverTargets = try config.parsedServerTargets()
    precondition(serverTargets.count > 0)

    // Start recording stats.
    self.statsPeriodStart = grpcTimeNow()
    self.cpuStatsPeriodStart = getResourceUsage()

    let requestMessage = try AsyncQPSClientImpl
      .makeClientRequest(payloadConfig: config.payloadConfig)

    // Start the requested number of channels.
    self.channelRepeaters = (0 ..< Int(config.clientChannels)).map { channelNumber in
      ChannelRepeater(
        target: serverTargets[channelNumber % serverTargets.count],
        requestMessage: requestMessage,
        config: config,
        eventLoop: eventLoopGroup.next()
      )
    }
  }

  /// Start the execution of the client.
  func startClient() {
    Task {
      try await withThrowingTaskGroup(of: Void.self) { group in
        for repeater in self.channelRepeaters {
          group.addTask {
            try await repeater.start()
          }
        }
        try await group.waitForAll()
      }
    }
  }

  /// Send current status back to the driver process.
  /// - parameters:
  ///     - reset: Should the stats reset after being sent.
  ///     - context: Calling context to allow results to be sent back to the driver.
  func sendStatus(
    reset: Bool,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ClientStatus>
  ) async throws {
    let currentTime = grpcTimeNow()
    let currentResourceUsage = getResourceUsage()
    var result = Grpc_Testing_ClientStatus()
    result.stats.timeElapsed = (currentTime - self.statsPeriodStart).asSeconds()
    result.stats.timeSystem = currentResourceUsage.systemTime - self.cpuStatsPeriodStart
      .systemTime
    result.stats.timeUser = currentResourceUsage.userTime - self.cpuStatsPeriodStart.userTime
    result.stats.cqPollCount = 0

    // Collect stats from each of the channels.
    var latencyHistogram = Histogram()
    var statusCounts = StatusCounts()
    for channelRepeater in self.channelRepeaters {
      let stats = channelRepeater.getStats(reset: reset)
      try! latencyHistogram.merge(source: stats.latencies)
      statusCounts.merge(source: stats.statuses)
    }
    result.stats.latencies = Grpc_Testing_HistogramData(from: latencyHistogram)
    result.stats.requestResults = statusCounts.toRequestResultCounts()
    self.logger.info("Sending client status")
    try await responseStream.send(result)

    if reset {
      self.statsPeriodStart = currentTime
      self.cpuStatsPeriodStart = currentResourceUsage
    }
  }

  /// Shut down the service.
  func shutdown() async throws {
    await withThrowingTaskGroup(of: Void.self) { group in
      for repeater in self.channelRepeaters {
        group.addTask {
          do {
            try await repeater.stop()
          } catch {
            self.logger.warning(
              "A channel repeater could not be stopped",
              metadata: ["error": "\(error)"]
            )
          }
        }
      }
    }
  }

  /// Make a request which can be sent to the server.
  private static func makeClientRequest(
    payloadConfig: Grpc_Testing_PayloadConfig
  ) throws -> Grpc_Testing_SimpleRequest {
    if let payload = payloadConfig.payload {
      switch payload {
      case .bytebufParams:
        throw GRPCStatus(code: .invalidArgument, message: "Byte buffer not supported.")
      case let .simpleParams(simpleParams):
        var result = Grpc_Testing_SimpleRequest()
        result.responseType = .compressable
        result.responseSize = simpleParams.respSize
        result.payload.type = .compressable
        let size = Int(simpleParams.reqSize)
        let body = Data(count: size)
        result.payload.body = body
        return result
      case .complexParams:
        throw GRPCStatus(
          code: .invalidArgument,
          message: "Complex params not supported."
        )
      }
    } else {
      // Default - simple proto without payloads.
      var result = Grpc_Testing_SimpleRequest()
      result.responseType = .compressable
      result.responseSize = 0
      result.payload.type = .compressable
      return result
    }
  }

  /// Class to manage a channel.  Repeatedly makes requests on that channel and records what happens.
  /// /// Class is marked as `@unchecked Sendable` because `ManagedAtomic<Bool>` doesn't conform
  /// to `Sendable`, but we know it's safe.
  private final class ChannelRepeater: @unchecked Sendable {
    private let channel: GRPCChannel
    private let eventLoop: EventLoop
    private let maxPermittedOutstandingRequests: Int

    private let stats: StatsWithLock

    /// Succeeds after a stop has been requested and all outstanding requests have completed.
    private let stopComplete: EventLoopPromise<Void>

    private let running = ManagedAtomic<Bool>(false)

    private let requestMaker: RequestMakerType

    init(
      target: ConnectionTarget,
      requestMessage: Grpc_Testing_SimpleRequest,
      config: Grpc_Testing_ClientConfig,
      eventLoop: EventLoop
    ) {
      self.eventLoop = eventLoop
      // 'try!' is fine; it'll only throw if we can't make an SSL context
      // TODO: Support TLS if requested.
      self.channel = try! GRPCChannelPool.with(
        target: target,
        transportSecurity: .plaintext,
        eventLoopGroup: eventLoop
      )

      let logger = Logger(label: "ChannelRepeater")
      let client = Grpc_Testing_BenchmarkServiceAsyncClient(channel: self.channel)
      self.maxPermittedOutstandingRequests = Int(config.outstandingRpcsPerChannel)
      self.stopComplete = eventLoop.makePromise()
      self.stats = StatsWithLock()

      self.requestMaker = RequestMakerType(
        config: config,
        client: client,
        requestMessage: requestMessage,
        logger: logger,
        stats: self.stats
      )
    }

    /// Launch as many requests as allowed on the channel. Must only be called once.
    private func launchRequests() async throws {
      let exchangedRunning = self.running.compareExchange(
        expected: false,
        desired: true,
        ordering: .relaxed
      )
      precondition(exchangedRunning.exchanged, "launchRequests should only be called once")

      try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0 ..< self.maxPermittedOutstandingRequests {
          group.addTask {
            try await self.requestMaker.makeRequest()
          }
        }

        /// While `running` is true, we'll keep launching new requests to
        /// maintain `maxPermittedOutstandingRequests` running
        /// at any given time.
        for try await _ in group {
          if self.running.load(ordering: .relaxed) {
            group.addTask {
              try await self.requestMaker.makeRequest()
            }
          }
        }
        self.stopIsComplete()
      }
    }

    /// Get stats for sending to the driver.
    /// - parameters:
    ///     - reset: Should the stats reset after copying.
    /// - returns: The statistics for this channel.
    func getStats(reset: Bool) -> Stats {
      return self.stats.copyData(reset: reset)
    }

    /// Start sending requests to the server.
    func start() async throws {
      try await self.launchRequests()
    }

    private func stopIsComplete() {
      // Close the connection then signal done.
      self.channel.close().cascade(to: self.stopComplete)
    }

    /// Stop sending requests to the server.
    /// - returns: A future which can be waited on to signal when all activity has ceased.
    func stop() async throws {
      self.requestMaker.requestStop()
      self.running.store(false, ordering: .relaxed)
      try await self.stopComplete.futureResult.get()
    }
  }
}

/// Create an asynchronous client of the requested type.
/// - parameters:
///     - config: Description of the client required.
/// - returns: The client created.
func makeAsyncClient(config: Grpc_Testing_ClientConfig) throws -> AsyncQPSClient {
  switch config.rpcType {
  case .unary:
    return try AsyncQPSClientImpl<AsyncUnaryRequestMaker>(config: config)
  case .streaming:
    return try AsyncQPSClientImpl<AsyncPingPongRequestMaker>(config: config)
  case .streamingFromClient,
       .streamingFromServer,
       .streamingBothWays:
    throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
  case .UNRECOGNIZED:
    throw GRPCStatus(code: .invalidArgument, message: "Unrecognised client rpc type")
  }
}
