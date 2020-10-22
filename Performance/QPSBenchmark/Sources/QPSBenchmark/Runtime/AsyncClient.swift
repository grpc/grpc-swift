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

import BenchmarkUtils
import Foundation
import GRPC
import Logging
import NIO

/// Client to make a series of asynchronous calls.
final class AsyncQPSClient<RequestMakerType: RequestMaker>: QPSClient {
  private let eventLoopGroup: MultiThreadedEventLoopGroup
  private let threadCount: Int

  private let logger = Logger(label: "AsyncQPSClient")

  private let channelRepeaters: [ChannelRepeater]

  private var statsPeriodStart: DispatchTime
  private var cpuStatsPeriodStart: CPUTime

  /// Initialise a client to send requests.
  /// - parameters:
  ///      - config: Config from the driver specifying how the client should behave.
  init(config: Grpc_Testing_ClientConfig) throws {
    // Parse possible invalid targets before code with side effects.
    let serverTargets = try config.parsedServerTargets()
    precondition(serverTargets.count > 0)

    // Setup threads
    let threadCount = config.threadsToUse()
    self.threadCount = threadCount
    self.logger.info("Sizing AsyncQPSClient", metadata: ["threads": "\(threadCount)"])
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)
    self.eventLoopGroup = eventLoopGroup

    // Start recording stats.
    self.statsPeriodStart = grpcTimeNow()
    self.cpuStatsPeriodStart = getResourceUsage()

    let requestMessage = try AsyncQPSClient
      .makeClientRequest(payloadConfig: config.payloadConfig)

    // Start the requested number of channels.
    self.channelRepeaters = (0 ..< Int(config.clientChannels)).map { channelNumber in
      ChannelRepeater(
        target: serverTargets[channelNumber % serverTargets.count],
        requestMessage: requestMessage,
        config: config,
        eventLoopGroup: eventLoopGroup
      )
    }

    // Start the train.
    for channelRepeater in self.channelRepeaters {
      channelRepeater.start()
    }
  }

  /// Send current status back to the driver process.
  /// - parameters:
  ///     - reset: Should the stats reset after being sent.
  ///     - context: Calling context to allow results to be sent back to the driver.
  func sendStatus(reset: Bool, context: StreamingResponseCallContext<Grpc_Testing_ClientStatus>) {
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
    self.logger.info("Sending response")
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
    let stoppedFutures = self.channelRepeaters.map { repeater in repeater.stop() }
    let allStopped = EventLoopFuture.andAllComplete(stoppedFutures, on: callbackLoop)
    return allStopped.flatMap { _ in
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

  /// Make a request which can be sent to the server.
  private static func makeClientRequest(payloadConfig: Grpc_Testing_PayloadConfig) throws
    -> Grpc_Testing_SimpleRequest {
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
  private class ChannelRepeater {
    private let connection: ClientConnection
    private let maxPermittedOutstandingRequests: Int

    private let stats: StatsWithLock

    /// Has a stop been requested - if it has don't submit any more
    /// requests and when all existing requests are complete signal
    /// using `stopComplete`
    private var stopRequested = false
    /// Succeeds after a stop has been requested and all outstanding requests have completed.
    private var stopComplete: EventLoopPromise<Void>
    private var numberOfOutstandingRequests = 0

    private var requestMaker: RequestMakerType

    init(target: HostAndPort,
         requestMessage: Grpc_Testing_SimpleRequest,
         config: Grpc_Testing_ClientConfig,
         eventLoopGroup: EventLoopGroup) {
      // TODO: Support TLS if requested.
      self.connection = ClientConnection.insecure(group: eventLoopGroup)
        .connect(host: target.host, port: target.port)

      let logger = Logger(label: "ChannelRepeater")
      let client = Grpc_Testing_BenchmarkServiceClient(channel: self.connection)
      self.maxPermittedOutstandingRequests = Int(config.outstandingRpcsPerChannel)
      self.stopComplete = self.connection.eventLoop.makePromise()
      self.stats = StatsWithLock()

      self.requestMaker = RequestMakerType(
        config: config,
        client: client,
        requestMessage: requestMessage,
        logger: logger,
        stats: self.stats
      )
    }

    /// Launch as many requests as allowed on the channel.
    /// This must be called from the connection eventLoop.
    private func launchRequests() {
      self.connection.eventLoop.preconditionInEventLoop()

      while self.canMakeRequest {
        self.makeRequestAndRepeat()
      }
    }

    /// Returns if it is permissible to make another request - ie we've not been asked to stop, and we're not at the limit of outstanding requests.
    private var canMakeRequest: Bool {
      self.connection.eventLoop.assertInEventLoop()
      return !self.stopRequested
        && self.numberOfOutstandingRequests < self.maxPermittedOutstandingRequests
    }

    /// If there is spare permitted capacity make a request and repeat when it is done.
    private func makeRequestAndRepeat() {
      self.connection.eventLoop.preconditionInEventLoop()
      // Check for capacity.
      if !self.canMakeRequest {
        return
      }
      self.numberOfOutstandingRequests += 1
      let resultStatus = self.requestMaker.makeRequest()

      // Wait for the request to complete.
      resultStatus.whenSuccess { status in
        self.requestCompleted(status: status)
      }
    }

    /// Call when a request has completed.
    /// Records stats and attempts to make more requests if there is available capacity.
    private func requestCompleted(status: GRPCStatus) {
      self.connection.eventLoop.preconditionInEventLoop()
      self.numberOfOutstandingRequests -= 1
      if self.stopRequested, self.numberOfOutstandingRequests == 0 {
        self.stopIsComplete()
      } else {
        // Try scheduling another request.
        self.makeRequestAndRepeat()
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
        self.requestMaker.requestStop()
        if self.numberOfOutstandingRequests == 0 {
          self.stopIsComplete()
        }
      }
      return self.stopComplete.futureResult
    }
  }
}

/// Create an asynchronous client of the requested type.
/// - parameters:
///     - config: Description of the client required.
/// - returns: The client created.
func makeAsyncClient(config: Grpc_Testing_ClientConfig) throws -> QPSClient {
  switch config.rpcType {
  case .unary:
    return try AsyncQPSClient<AsyncUnaryRequestMaker>(config: config)
  case .streaming:
    return try AsyncQPSClient<AsyncPingPongRequestMaker>(config: config)
  case .streamingFromClient:
    throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
  case .streamingFromServer:
    throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
  case .streamingBothWays:
    throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
  case .UNRECOGNIZED:
    throw GRPCStatus(code: .invalidArgument, message: "Unrecognised client rpc type")
  }
}
