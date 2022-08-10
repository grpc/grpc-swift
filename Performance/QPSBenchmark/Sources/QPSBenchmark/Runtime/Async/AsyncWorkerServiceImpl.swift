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

// Implementation of the control service for communication with the driver process.
actor AsyncWorkerServiceImpl: Grpc_Testing_WorkerServiceAsyncProvider {
  let interceptors: Grpc_Testing_WorkerServiceServerInterceptorFactoryProtocol? = nil

  private let finishedPromise: EventLoopPromise<Void>
  private let serverPortOverride: Int?

  private var runningServer: AsyncQPSServer?
  private var runningClient: AsyncQPSClient?

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
  func runServer(
    requestStream: GRPCAsyncRequestStream<Grpc_Testing_ServerArgs>,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ServerStatus>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    context.request.logger.info("runServer stream started.")
    for try await request in requestStream {
      try await self.handleServerMessage(
        context: context,
        args: request,
        responseStream: responseStream
      )
    }
    try await self.handleServerEnd(context: context)
  }

  /// Start client with specified workload.
  /// First request sent specifies the ClientConfig followed by ClientStatus
  /// response. After that, a "Mark" can be sent anytime to request the latest
  /// stats. Closing the stream will initiate shutdown of the test client
  /// and once the shutdown has finished, the OK status is sent to terminate
  /// this RPC.
  func runClient(
    requestStream: GRPCAsyncRequestStream<Grpc_Testing_ClientArgs>,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ClientStatus>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await request in requestStream {
      try await self.handleClientMessage(
        context: context,
        args: request,
        responseStream: responseStream
      )
    }
    try await self.handleClientEnd(context: context)
  }

  /// Just return the core count - unary call
  func coreCount(
    request: Grpc_Testing_CoreRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Grpc_Testing_CoreResponse {
    context.request.logger.notice("coreCount queried")
    return Grpc_Testing_CoreResponse.with { $0.cores = Int32(System.coreCount) }
  }

  /// Quit this worker
  func quitWorker(
    request: Grpc_Testing_Void,
    context: GRPCAsyncServerCallContext
  ) -> Grpc_Testing_Void {
    context.request.logger.warning("quitWorker called")
    self.finishedPromise.succeed(())
    return Grpc_Testing_Void()
  }

  // MARK: Run Server

  /// Handle a message received from the driver about operating as a server.
  private func handleServerMessage(
    context: GRPCAsyncServerCallContext,
    args: Grpc_Testing_ServerArgs,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ServerStatus>
  ) async throws {
    switch args.argtype {
    case let .some(.setup(serverConfig)):
      try await self.handleServerSetup(
        context: context,
        config: serverConfig,
        responseStream: responseStream
      )
    case let .some(.mark(mark)):
      try await self.handleServerMarkRequested(
        context: context,
        mark: mark,
        responseStream: responseStream
      )
    case .none:
      ()
    }
  }

  /// Handle a request to setup a server.
  /// Makes a new server and sets it running.
  private func handleServerSetup(
    context: GRPCAsyncServerCallContext,
    config: Grpc_Testing_ServerConfig,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ServerStatus>
  ) async throws {
    context.request.logger.info("server setup requested")
    guard self.runningServer == nil else {
      context.request.logger.error("server already running")
      throw GRPCStatus(
        code: GRPCStatus.Code.resourceExhausted,
        message: "Server worker busy"
      )
    }
    try await self.runServerBody(
      context: context,
      serverConfig: config,
      responseStream: responseStream
    )
  }

  /// Gathers stats and returns them to the driver process.
  private func handleServerMarkRequested(
    context: GRPCAsyncServerCallContext,
    mark: Grpc_Testing_Mark,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ServerStatus>
  ) async throws {
    context.request.logger.info("server mark requested")
    guard let runningServer = self.runningServer else {
      context.request.logger.error("server not running")
      throw GRPCStatus(
        code: GRPCStatus.Code.failedPrecondition,
        message: "Server not running"
      )
    }
    try await runningServer.sendStatus(reset: mark.reset, responseStream: responseStream)
  }

  /// Handle a message from the driver asking this server function to stop running.
  private func handleServerEnd(context: GRPCAsyncServerCallContext) async throws {
    context.request.logger.info("runServer stream ended.")
    if let runningServer = self.runningServer {
      self.runningServer = nil
      try await runningServer.shutdown()
    }
  }

  // MARK: Create Server

  /// Start a server running of the requested type.
  private func runServerBody(
    context: GRPCAsyncServerCallContext,
    serverConfig: Grpc_Testing_ServerConfig,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ServerStatus>
  ) async throws {
    var serverConfig = serverConfig
    self.serverPortOverride.map { serverConfig.port = Int32($0) }

    self.runningServer = try await AsyncWorkerServiceImpl.createServer(
      context: context,
      config: serverConfig,
      responseStream: responseStream
    )
  }

  private static func sendServerInfo(
    _ serverInfo: ServerInfo,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ServerStatus>
  ) async throws {
    var response = Grpc_Testing_ServerStatus()
    response.cores = Int32(serverInfo.threadCount)
    response.port = Int32(serverInfo.port)
    try await responseStream.send(response)
  }

  /// Create a server of the requested type.
  private static func createServer(
    context: GRPCAsyncServerCallContext,
    config: Grpc_Testing_ServerConfig,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ServerStatus>
  ) async throws -> AsyncQPSServer {
    context.request.logger.info(
      "Starting server",
      metadata: ["type": .stringConvertible(config.serverType)]
    )

    switch config.serverType {
    case .asyncServer:
      let asyncServer = try await AsyncQPSServerImpl(config: config)
      let serverInfo = asyncServer.serverInfo
      try await self.sendServerInfo(serverInfo, responseStream: responseStream)
      return asyncServer
    case .syncServer,
         .asyncGenericServer,
         .otherServer,
         .callbackServer:
      throw GRPCStatus(code: .unimplemented, message: "Server Type not implemented")
    case .UNRECOGNIZED:
      throw GRPCStatus(code: .invalidArgument, message: "Unrecognised server type")
    }
  }

  // MARK: Run Client

  /// Handle a message from the driver about operating as a client.
  private func handleClientMessage(
    context: GRPCAsyncServerCallContext,
    args: Grpc_Testing_ClientArgs,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ClientStatus>
  ) async throws {
    switch args.argtype {
    case let .some(.setup(clientConfig)):
      try await self.handleClientSetup(
        context: context,
        config: clientConfig,
        responseStream: responseStream
      )
      self.runningClient!.startClient()
    case let .some(.mark(mark)):
      // Capture stats
      try await self.handleClientMarkRequested(
        context: context,
        mark: mark,
        responseStream: responseStream
      )
    case .none:
      ()
    }
  }

  /// Setup a client as described by the message from the driver.
  private func handleClientSetup(
    context: GRPCAsyncServerCallContext,
    config: Grpc_Testing_ClientConfig,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ClientStatus>
  ) async throws {
    context.request.logger.info("client setup requested")
    guard self.runningClient == nil else {
      context.request.logger.error("client already running")
      throw GRPCStatus(
        code: GRPCStatus.Code.resourceExhausted,
        message: "Client worker busy"
      )
    }
    try self.runClientBody(context: context, clientConfig: config)
    // Initial status is the default (in C++)
    try await responseStream.send(Grpc_Testing_ClientStatus())
  }

  /// Captures stats and send back to driver process.
  private func handleClientMarkRequested(
    context: GRPCAsyncServerCallContext,
    mark: Grpc_Testing_Mark,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_ClientStatus>
  ) async throws {
    context.request.logger.info("client mark requested")
    guard let runningClient = self.runningClient else {
      context.request.logger.error("client not running")
      throw GRPCStatus(
        code: GRPCStatus.Code.failedPrecondition,
        message: "Client not running"
      )
    }
    try await runningClient.sendStatus(reset: mark.reset, responseStream: responseStream)
  }

  /// Call when an end message has been received.
  /// Causes the running client to shutdown.
  private func handleClientEnd(context: GRPCAsyncServerCallContext) async throws {
    context.request.logger.info("runClient ended")
    if let runningClient = self.runningClient {
      self.runningClient = nil
      try await runningClient.shutdown()
    }
  }

  // MARK: Create Client

  /// Setup and run a client of the requested type.
  private func runClientBody(
    context: GRPCAsyncServerCallContext,
    clientConfig: Grpc_Testing_ClientConfig
  ) throws {
    self.runningClient = try AsyncWorkerServiceImpl.makeClient(
      context: context,
      clientConfig: clientConfig
    )
  }

  /// Create a client of the requested type.
  private static func makeClient(
    context: GRPCAsyncServerCallContext,
    clientConfig: Grpc_Testing_ClientConfig
  ) throws -> AsyncQPSClient {
    switch clientConfig.clientType {
    case .asyncClient:
      if case .bytebufParams = clientConfig.payloadConfig.payload {
        throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
      }
      return try makeAsyncClient(config: clientConfig)
    case .syncClient,
         .otherClient,
         .callbackClient:
      throw GRPCStatus(code: .unimplemented, message: "Client Type not implemented")
    case .UNRECOGNIZED:
      throw GRPCStatus(code: .invalidArgument, message: "Unrecognised client type")
    }
  }
}
