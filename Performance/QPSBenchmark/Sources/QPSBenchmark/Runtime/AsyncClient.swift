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

import NIO
import GRPC
import Logging
import Foundation
import BenchmarkUtils

/// Client to make a series of asynchronous unary calls.
final class AsyncUnaryQpsClient: QpsClient {
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let threadCount: Int

    private let logger = Logger(label: "AsyncQpsClient")

    private let channelRepeaters: [ChannelRepeater]

    private var statsPeriodStart: Date
    private var cpuStatsPeriodStart: CPUTime

    /// Initialise a client to send unary requests.
    /// - parameters:
    ///      - config: Config from the driver specifying how the client should behave.
    init(config: Grpc_Testing_ClientConfig) throws {
        // Parse possible invalid targets before code with side effects.
        let serverTargets = try config.parsedServerTargets()

        // Setup threads
        let threadCount = config.threadsToUse()
        self.threadCount = threadCount
        self.logger.info("Sizing AsyncQpsClient", metadata: ["threads": "\(threadCount)"])
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)

        // Start recording stats.
        self.statsPeriodStart = grpcTimeNow()
        self.cpuStatsPeriodStart = getResourceUsage()

        // Start the requested number of channels.
        precondition(serverTargets.count > 0)
        var channelRepeaters : [ChannelRepeater] = []
        for channelNumber in 0..<Int(config.clientChannels) {
            channelRepeaters.append(ChannelRepeater(target: serverTargets[channelNumber % serverTargets.count],
                                                    config: config,
                                                    eventLoopGroup: eventLoopGroup))
        }
        self.channelRepeaters = channelRepeaters

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
        result.stats.timeElapsed = currentTime.timeIntervalSince(self.statsPeriodStart)
        result.stats.timeSystem = currentResourceUsage.systemTime - self.cpuStatsPeriodStart.systemTime
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
        let promise: EventLoopPromise<Void> = callbackLoop.makePromise()
        let stoppedFutures = self.channelRepeaters.map { repeater in repeater.stop() }
        let allStopped = EventLoopFuture<Void>.reduce((),
                                                      stoppedFutures,
                                                      on: callbackLoop, { (_, _) -> Void in return () } )
        _ = allStopped.always { result in
            return self.eventLoopGroup.shutdownGracefully { error in
                if let error = error {
                    promise.fail(error)
                } else {
                    promise.succeed(())
                }
            }
        }
        return promise.futureResult
    }

    /// Class to manage a channel.  Repeatedly makes requests on that channel and records what happens.
    private class ChannelRepeater {
        private let connection: ClientConnection
        private let client: Grpc_Testing_BenchmarkServiceClient
        private let payloadConfig: Grpc_Testing_PayloadConfig
        private let logger = Logger(label: "ChannelRepeater")
        private let maxPermittedOutstandingRequests: Int
        
        private var stats: StatsWithLock

        private var stopRequested = false
        private var stopComplete: EventLoopPromise<Void>
        private var numberOfOutstandingRequests = 0

        init(target: HostAndPort,
             config : Grpc_Testing_ClientConfig,
             eventLoopGroup: EventLoopGroup) {
            self.connection = ClientConnection.insecure(group: eventLoopGroup)
                .connect(host: target.host, port: target.port)
            self.client = Grpc_Testing_BenchmarkServiceClient(channel: connection)
            self.payloadConfig = config.payloadConfig
            self.maxPermittedOutstandingRequests = Int(config.outstandingRpcsPerChannel)
            self.stopComplete = connection.eventLoop.makePromise()
            self.stats = StatsWithLock()
        }

        /// Launch as many requests as allowed on the channel.
        private func launchRequests() throws {
            precondition(self.connection.eventLoop.inEventLoop)
            while !self.stopRequested && self.numberOfOutstandingRequests < self.maxPermittedOutstandingRequests {
                try makeRequestAndRepeat()
            }
        }

        /// If there is spare permitted capacity make a request and repeat when it is done.
        private func makeRequestAndRepeat() throws {
            // Check for capacity.
            if self.stopRequested || self.numberOfOutstandingRequests >= self.maxPermittedOutstandingRequests {
                return
            }
            let startTime = grpcTimeNow()
            let request = try ChannelRepeater.createClientRequest(payloadConfig: self.payloadConfig)
            self.numberOfOutstandingRequests += 1
            let result = client.unaryCall(request)

            // Wait for the request to complete.
            _ = result.status.map { status in
                self.numberOfOutstandingRequests -= 1
                if status.isOk {
                    let endTime = grpcTimeNow()
                    self.recordLatency(endTime.timeIntervalSince(startTime))
                } else {
                    self.logger.error("Bad status from unary request", metadata: ["status": "\(status)"])
                }
                if self.stopRequested && self.numberOfOutstandingRequests == 0 {
                    self.stopIsComplete()
                } else {
                    // Try scheduling another request.
                    try! self.launchRequests()
                }
            }
        }

        private func recordLatency(_ latency: TimeInterval) {
            self.stats.add(latency: latency * 1e9)
        }

        /// Get stats for sending to the driver.
        /// - parameters:
        ///     - reset: Should the stats reset after copying.
        /// - returns: The statistics for this channel.
        func getStats(reset: Bool) -> Stats {
            return self.stats.copyData(reset: reset)
        }

        private static func createClientRequest(payloadConfig: Grpc_Testing_PayloadConfig) throws -> Grpc_Testing_SimpleRequest {
            if let payload = payloadConfig.payload {
                switch payload {
                case .bytebufParams(_):
                    throw GRPCStatus(code: .invalidArgument, message: "Byte buffer not supported.")
                case .simpleParams(let simpleParams):
                    var result = Grpc_Testing_SimpleRequest()
                    result.responseType = .compressable
                    result.responseSize = simpleParams.respSize
                    result.payload.type = .compressable
                    let size = Int(simpleParams.reqSize)
                    let body = Data(count: size)
                    result.payload.body = body
                    return result
                case .complexParams(_):
                    throw GRPCStatus(code: .invalidArgument, message: "Complex params not supported.")
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

        /// Start sending requests to the server.
        func start() {
            if self.connection.eventLoop.inEventLoop {
                try! self.launchRequests()
            } else {
                self.connection.eventLoop.execute {
                    try! self.launchRequests()
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

/// Create an asynchronous client of the requested type.
/// - parameters:
///     - config: Description of the client required.
/// - returns: The client created.
func createAsyncClient(config : Grpc_Testing_ClientConfig) throws -> QpsClient {
    switch config.rpcType {    
    case .unary:
        return try AsyncUnaryQpsClient(config: config)
    case .streaming:
        throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
    case .streamingFromClient:
        throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
    case .streamingFromServer:
        throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
    case .streamingBothWays:
        throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
    case .UNRECOGNIZED(_):
        throw GRPCStatus(code: .invalidArgument, message: "Unrecognised client rpc type")
    }
}
