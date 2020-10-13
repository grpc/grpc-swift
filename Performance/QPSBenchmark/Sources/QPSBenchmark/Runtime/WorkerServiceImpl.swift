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

// Implementation of the control service for communication with the driver process.
class WorkerServiceImpl: Grpc_Testing_WorkerServiceProvider {
    private let finishedPromise: EventLoopPromise<Void>
    private let serverPortOverride: Int?

    private var runningServer: QpsServer? = nil
    private var runningClient: QpsClient? = nil

    /// Initialise.
    /// - parameters:
    ///     - finishedPromise:  Promise to complete when the server has finished running.
    ///     - serverPortOverride: An override to port number requested by the driver process.
    init(finishedPromise: EventLoopPromise<Void>, serverPortOverride: Int?) {
        self.finishedPromise = finishedPromise
        self.serverPortOverride = serverPortOverride
    }

    /// Start server with specified workload.
    /// First request sent specifies the ServerConfig followed by ServerStatus
    /// response. After that, a "Mark" can be sent anytime to request the latest
    /// stats. Closing the stream will initiate shutdown of the test server
    /// and once the shutdown has finished, the OK status is sent to terminate
    /// this RPC.
    func runServer(context: StreamingResponseCallContext<Grpc_Testing_ServerStatus>) -> EventLoopFuture<(StreamEvent<Grpc_Testing_ServerArgs>) -> Void> {
        context.logger.info("runServer stream started.")
        return context.eventLoop.makeSucceededFuture({ event in
            switch event {
            case .message(let serverArgs):
                if let argType = serverArgs.argtype {
                    switch argType {
                    case .setup(let serverConfig):
                        context.logger.info("server setup requested")
                        guard self.runningServer == nil else {
                            context.logger.error("server already running")
                            context.statusPromise.fail(GRPCStatus(code: GRPCStatus.Code.resourceExhausted,
                                                                  message: "Server worker busy"))
                            return
                        }
                        self.runServerBody(context: context, serverConfig: serverConfig)
                    case .mark(let mark):
                        context.logger.info("server mark requested")
                        guard let runningServer = self.runningServer else {
                            context.logger.error("server not running")
                            context.statusPromise.fail(GRPCStatus(code: GRPCStatus.Code.failedPrecondition,
                                                                  message: "Server not running"))
                            return
                        }
                        runningServer.sendStatus(reset: mark.reset, context: context)
                    }
                }
            case .end:
                context.logger.info("runServer stream ended.")
                if let runningServer = self.runningServer {
                    self.runningServer = nil
                    let shutdownFuture = runningServer.shutdown(callbackLoop: context.eventLoop)
                    shutdownFuture.map { () in
                        return GRPCStatus(code: .ok, message: nil)
                    }.cascade(to: context.statusPromise)

                } else {
                    context.statusPromise.succeed(.ok)
                }
            }
        })
    }

    /// Start client with specified workload.
    /// First request sent specifies the ClientConfig followed by ClientStatus
    /// response. After that, a "Mark" can be sent anytime to request the latest
    /// stats. Closing the stream will initiate shutdown of the test client
    /// and once the shutdown has finished, the OK status is sent to terminate
    /// this RPC.
    func runClient(context: StreamingResponseCallContext<Grpc_Testing_ClientStatus>) -> EventLoopFuture<(StreamEvent<Grpc_Testing_ClientArgs>) -> Void> {
        context.logger.info("runClient stream started")
        return context.eventLoop.makeSucceededFuture( { event in
            switch event {
            case .message(let clientArgs):
                if let argType = clientArgs.argtype {
                    switch argType {
                    case .setup(let clientConfig):
                        context.logger.info("client setup requested")
                        guard self.runningClient == nil else {
                            context.logger.error("client already running")
                            context.statusPromise.fail(GRPCStatus(code: GRPCStatus.Code.resourceExhausted,
                                                                  message: "Client worker busy"))
                            return
                        }
                        self.runClientBody(context: context, clientConfig: clientConfig)
                        // Initial status is the default (in C++)
                        _ = context.sendResponse(Grpc_Testing_ClientStatus())
                    case .mark(let mark):
                        // Capture stats
                        context.logger.info("client mark requested")
                        guard let runningClient = self.runningClient else {
                            context.logger.error("client not running")
                            context.statusPromise.fail(GRPCStatus(code: GRPCStatus.Code.failedPrecondition,
                                                                  message: "Client not running"))
                            return
                        }
                        runningClient.sendStatus(reset: mark.reset, context: context)
                    }
                }
            case .end:
                context.logger.info("runClient ended")
                // Shutdown
                if let runningClient = self.runningClient {
                    self.runningClient = nil
                    let shutdownFuture = runningClient.shutdown(callbackLoop: context.eventLoop)
                    shutdownFuture.map { () in
                        return GRPCStatus(code: .ok, message: nil)
                    }.cascade(to: context.statusPromise)
                } else {
                    context.statusPromise.succeed(.ok)
                }
            }
        })
    }

    /// Just return the core count - unary call
    func coreCount(request: Grpc_Testing_CoreRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Grpc_Testing_CoreResponse> {
        context.logger.notice("coreCount queried")
        let cores = Grpc_Testing_CoreResponse.with { $0.cores = Int32(System.coreCount) }
        return context.eventLoop.makeSucceededFuture(cores)
    }

    /// Quit this worker
    func quitWorker(request: Grpc_Testing_Void, context: StatusOnlyCallContext) -> EventLoopFuture<Grpc_Testing_Void> {
        context.logger.warning("quitWorker called")
        self.finishedPromise.succeed(())
        return context.eventLoop.makeSucceededFuture(Grpc_Testing_Void())
    }

    // MARK: Create Server
    private func runServerBody(context: StreamingResponseCallContext<Grpc_Testing_ServerStatus>,
                               serverConfig: Grpc_Testing_ServerConfig) {
        var serverConfig = serverConfig
        self.serverPortOverride.map { serverConfig.port = Int32($0) }

        do {
            self.runningServer = try WorkerServiceImpl.createServer(context: context, config: serverConfig)
        }
        catch {
            context.statusPromise.fail(error)
        }
    }

    private static func createServer(context: StreamingResponseCallContext<Grpc_Testing_ServerStatus>,
                                     config : Grpc_Testing_ServerConfig) throws -> QpsServer {
        context.logger.info("Starting server", metadata: ["type": .stringConvertible(config.serverType)])

        switch config.serverType {
        case .syncServer:
            throw GRPCStatus(code: .unimplemented, message: "Server Type not implemented")
        case .asyncServer:
            let asyncServer = AsyncQpsServer(config: config,
                                             whenBound: { serverInfo in
                                                var response = Grpc_Testing_ServerStatus()
                                                response.cores = Int32(serverInfo.threadCount)
                                                response.port = Int32(serverInfo.port)
                                                _ = context.sendResponse(response)
                                             })
            return asyncServer
        case .asyncGenericServer:
            throw GRPCStatus(code: .unimplemented, message: "Server Type not implemented")
        case .otherServer:
            throw GRPCStatus(code: .unimplemented, message: "Server Type not implemented")
        case .callbackServer:
            throw GRPCStatus(code: .unimplemented, message: "Server Type not implemented")
        case .UNRECOGNIZED(_):
            throw GRPCStatus(code: .invalidArgument, message: "Unrecognised server type")
        }
    }

    // MARK: Create Client
    private func runClientBody(context: StreamingResponseCallContext<Grpc_Testing_ClientStatus>,
                               clientConfig: Grpc_Testing_ClientConfig) {
        do {
            self.runningClient = try WorkerServiceImpl.createClient(context: context, clientConfig: clientConfig)
        }
        catch {
            context.statusPromise.fail(error)
        }
    }

    private static func createClient(context: StreamingResponseCallContext<Grpc_Testing_ClientStatus>,
                                     clientConfig: Grpc_Testing_ClientConfig) throws -> QpsClient {
        switch clientConfig.clientType {
        case .syncClient:
            throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
        case .asyncClient:
            if let payloadConfig = clientConfig.payloadConfig.payload {
                switch payloadConfig {
                case .bytebufParams(_):
                    throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
                case .simpleParams(_):
                    return try createAsyncClient(config: clientConfig)
                case .complexParams(_):
                    return try createAsyncClient(config: clientConfig)
                }
            } else {
                // If there are no parameters assume simple.
                return try createAsyncClient(config: clientConfig)
            }
        case .otherClient:
            throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
        case .callbackClient:
            throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
        case .UNRECOGNIZED(_):
            throw GRPCStatus(code: .invalidArgument, message: "Unrecognised client type")
        }
    }
}

