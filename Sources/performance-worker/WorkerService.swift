/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

import GRPCCore
import GRPCHTTP2Core
import GRPCHTTP2TransportNIOPosix
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class WorkerService: Sendable {
  private let state: NIOLockedValueBox<State>

  init() {
    self.state = NIOLockedValueBox(State())
  }

  private struct State {
    private var role: Role

    enum Role {
      case none
      case client(Client)
      case server(Server)
    }

    struct Server {
      var server: GRPCServer
      var stats: ServerStats
      var eventLoopGroup: MultiThreadedEventLoopGroup
    }

    struct Client {
      var clients: [BenchmarkClient]
      var stats: ClientStats
      var rpcStats: RPCStats
    }

    init() {
      self.role = .none
    }

    mutating func collectServerStats(replaceWith newStats: ServerStats? = nil) -> ServerStats? {
      switch self.role {
      case var .server(serverState):
        let stats = serverState.stats
        if let newStats = newStats {
          serverState.stats = newStats
          self.role = .server(serverState)
        }
        return stats
      case .client, .none:
        return nil
      }
    }

    mutating func collectClientStats(
      replaceWith newStats: ClientStats? = nil
    ) -> (ClientStats, RPCStats)? {
      switch self.role {
      case var .client(state):
        // Grab the existing stats and update if necessary.
        let stats = state.stats
        if let newStats = newStats {
          state.stats = newStats
        }

        // Merge in RPC stats from each client.
        for client in state.clients {
          try? state.rpcStats.merge(client.currentStats)
        }

        self.role = .client(state)
        return (stats, state.rpcStats)

      case .server, .none:
        return nil
      }
    }

    enum OnStartedServer {
      case runServer
      case invalidState(RPCError)
    }

    mutating func startedServer(
      _ server: GRPCServer,
      stats: ServerStats,
      eventLoopGroup: MultiThreadedEventLoopGroup
    ) -> OnStartedServer {
      let action: OnStartedServer

      switch self.role {
      case .none:
        let state = State.Server(server: server, stats: stats, eventLoopGroup: eventLoopGroup)
        self.role = .server(state)
        action = .runServer
      case .server:
        let error = RPCError(code: .alreadyExists, message: "A server has already been set up.")
        action = .invalidState(error)
      case .client:
        let error = RPCError(code: .failedPrecondition, message: "This worker has a client setup.")
        action = .invalidState(error)
      }

      return action
    }

    enum OnStartedClients {
      case runClients
      case invalidState(RPCError)
    }

    mutating func startedClients(
      _ clients: [BenchmarkClient],
      stats: ClientStats,
      rpcStats: RPCStats
    ) -> OnStartedClients {
      let action: OnStartedClients

      switch self.role {
      case .none:
        let state = State.Client(clients: clients, stats: stats, rpcStats: rpcStats)
        self.role = .client(state)
        action = .runClients
      case .server:
        let error = RPCError(code: .alreadyExists, message: "This worker has a server setup.")
        action = .invalidState(error)
      case .client:
        let error = RPCError(
          code: .failedPrecondition,
          message: "Clients have already been set up."
        )
        action = .invalidState(error)
      }

      return action
    }

    enum OnServerShutDown {
      case shutdown(MultiThreadedEventLoopGroup)
      case nothing
    }

    mutating func serverShutdown() -> OnServerShutDown {
      switch self.role {
      case .client:
        preconditionFailure("Invalid state")
      case .server(let state):
        self.role = .none
        return .shutdown(state.eventLoopGroup)
      case .none:
        return .nothing
      }
    }

    enum OnStopListening {
      case stopListening(GRPCServer)
      case nothing
    }

    func stopListening() -> OnStopListening {
      switch self.role {
      case .client:
        preconditionFailure("Invalid state")
      case .server(let state):
        return .stopListening(state.server)
      case .none:
        return .nothing
      }
    }

    enum OnCloseClient {
      case close([BenchmarkClient])
      case nothing
    }

    mutating func closeClients() -> OnCloseClient {
      switch self.role {
      case .client(let state):
        self.role = .none
        return .close(state.clients)
      case .server:
        preconditionFailure("Invalid state")
      case .none:
        return .nothing
      }
    }

    enum OnQuitWorker {
      case shutDownServer(GRPCServer)
      case shutDownClients([BenchmarkClient])
      case nothing
    }

    mutating func quit() -> OnQuitWorker {
      switch self.role {
      case .none:
        return .nothing
      case .client(let state):
        self.role = .none
        return .shutDownClients(state.clients)
      case .server(let state):
        self.role = .none
        return .shutDownServer(state.server)
      }
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension WorkerService: Grpc_Testing_WorkerService.ServiceProtocol {
  func quitWorker(
    request: ServerRequest.Single<Grpc_Testing_Void>
  ) async throws -> ServerResponse.Single<Grpc_Testing_Void> {
    let onQuit = self.state.withLockedValue { $0.quit() }

    switch onQuit {
    case .nothing:
      ()

    case .shutDownClients(let clients):
      for client in clients {
        client.shutdown()
      }

    case .shutDownServer(let server):
      server.stopListening()
    }

    return ServerResponse.Single(message: Grpc_Testing_Void())
  }

  func coreCount(
    request: ServerRequest.Single<Grpc_Testing_CoreRequest>
  ) async throws -> ServerResponse.Single<Grpc_Testing_CoreResponse> {
    let coreCount = System.coreCount
    return ServerResponse.Single(
      message: Grpc_Testing_WorkerService.Method.CoreCount.Output.with {
        $0.cores = Int32(coreCount)
      }
    )
  }

  func runServer(
    request: ServerRequest.Stream<Grpc_Testing_ServerArgs>
  ) async throws -> ServerResponse.Stream<Grpc_Testing_ServerStatus> {
    return ServerResponse.Stream { writer in
      try await withThrowingTaskGroup(of: Void.self) { group in
        for try await message in request.messages {
          switch message.argtype {
          case let .some(.setup(serverConfig)):
            let (server, transport) = try await self.startServer(serverConfig)
            group.addTask {
              let result: Result<Void, Error>

              do {
                try await server.run()
                result = .success(())
              } catch {
                result = .failure(error)
              }

              switch self.state.withLockedValue({ $0.serverShutdown() }) {
              case .shutdown(let eventLoopGroup):
                try await eventLoopGroup.shutdownGracefully()
              case .nothing:
                ()
              }

              try result.get()
            }

            // Wait for the server to bind.
            let address = try await transport.listeningAddress

            let port: Int
            if let ipv4 = address.ipv4 {
              port = ipv4.port
            } else if let ipv6 = address.ipv6 {
              port = ipv6.port
            } else {
              throw RPCError(
                code: .internalError,
                message: "Server listening on unsupported address '\(address)'"
              )
            }

            // Tell the client what port the server is listening on.
            let message = Grpc_Testing_ServerStatus.with { $0.port = Int32(port) }
            try await writer.write(message)

          case let .some(.mark(mark)):
            let response = try await self.makeServerStatsResponse(reset: mark.reset)
            try await writer.write(response)

          case .none:
            ()
          }
        }

        // Request stream ended, tell the server to stop listening. Once it's finished it will
        // shutdown its ELG.
        switch self.state.withLockedValue({ $0.stopListening() }) {
        case .stopListening(let server):
          server.stopListening()
        case .nothing:
          ()
        }
      }

      return [:]
    }
  }

  func runClient(
    request: ServerRequest.Stream<Grpc_Testing_ClientArgs>
  ) async throws -> ServerResponse.Stream<Grpc_Testing_ClientStatus> {
    return ServerResponse.Stream { writer in
      try await withThrowingTaskGroup(of: Void.self) { group in
        for try await message in request.messages {
          switch message.argtype {
          case let .setup(config):
            // Create the clients with the initial stats.
            let clients = try await self.setupClients(config)

            for client in clients {
              group.addTask {
                try await client.run()
              }
            }

            let message = try await self.makeClientStatsResponse(reset: false)
            try await writer.write(message)

          case let .mark(mark):
            let response = try await self.makeClientStatsResponse(reset: mark.reset)
            try await writer.write(response)

          case .none:
            ()
          }
        }

        switch self.state.withLockedValue({ $0.closeClients() }) {
        case .close(let clients):
          for client in clients {
            client.shutdown()
          }
        case .nothing:
          ()
        }

        try await group.waitForAll()

        return [:]
      }
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension WorkerService {
  private func startServer(
    _ serverConfig: Grpc_Testing_ServerConfig
  ) async throws -> (GRPCServer, HTTP2ServerTransport.Posix) {
    // Prepare an ELG, the test might require more than the default of one.
    let numberOfThreads: Int
    if serverConfig.asyncServerThreads > 0 {
      numberOfThreads = Int(serverConfig.asyncServerThreads)
    } else {
      numberOfThreads = System.coreCount
    }
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)

    // Don't restrict the max payload size, the client is always trusted.
    var config = HTTP2ServerTransport.Posix.Config.defaults
    config.rpc.maxRequestPayloadSize = .max

    let transport = HTTP2ServerTransport.Posix(
      address: .ipv4(host: "127.0.0.1", port: Int(serverConfig.port)),
      config: config,
      eventLoopGroup: eventLoopGroup
    )

    let server = GRPCServer(transport: transport, services: [BenchmarkService()])
    let stats = try await ServerStats()

    // Hold on to the server and ELG in the state machine.
    let action = self.state.withLockedValue {
      $0.startedServer(server, stats: stats, eventLoopGroup: eventLoopGroup)
    }

    switch action {
    case .runServer:
      return (server, transport)
    case .invalidState(let error):
      server.stopListening()
      try await eventLoopGroup.shutdownGracefully()
      throw error
    }
  }

  private func makeServerStatsResponse(
    reset: Bool
  ) async throws -> Grpc_Testing_WorkerService.Method.RunServer.Output {
    let currentStats = try await ServerStats()
    let initialStats = self.state.withLockedValue { state in
      return state.collectServerStats(replaceWith: reset ? currentStats : nil)
    }

    guard let initialStats = initialStats else {
      throw RPCError(
        code: .notFound,
        message: "There are no initial server stats. A server must be setup before calling 'mark'."
      )
    }

    let differences = currentStats.difference(to: initialStats)
    return Grpc_Testing_WorkerService.Method.RunServer.Output.with {
      $0.stats = Grpc_Testing_ServerStats.with {
        $0.idleCpuTime = differences.idleCPUTime
        $0.timeElapsed = differences.time
        $0.timeSystem = differences.systemTime
        $0.timeUser = differences.userTime
        $0.totalCpuTime = differences.totalCPUTime
      }
    }
  }

  private func setupClients(_ config: Grpc_Testing_ClientConfig) async throws -> [BenchmarkClient] {
    guard let rpcType = BenchmarkClient.RPCType(config.rpcType) else {
      throw RPCError(code: .invalidArgument, message: "Unknown RPC type")
    }

    // Parse the server targets into resolvable targets.
    let ipv4Addresses = try self.parseServerTargets(config.serverTargets)
    let target = ResolvableTargets.IPv4(addresses: ipv4Addresses)

    var clients = [BenchmarkClient]()
    for _ in 0 ..< config.clientChannels {
      let transport = try HTTP2ClientTransport.Posix(target: target)
      let client = BenchmarkClient(
        client: GRPCClient(transport: transport),
        concurrentRPCs: Int(config.outstandingRpcsPerChannel),
        rpcType: rpcType,
        messagesPerStream: Int(config.messagesPerStream),
        protoParams: config.payloadConfig.simpleParams,
        histogramParams: config.histogramParams
      )

      clients.append(client)
    }

    let stats = ClientStats()
    let histogram = RPCStats.LatencyHistogram(
      resolution: config.histogramParams.resolution,
      maxBucketStart: config.histogramParams.maxPossible
    )
    let rpcStats = RPCStats(latencyHistogram: histogram)

    let action = self.state.withLockedValue { state in
      state.startedClients(clients, stats: stats, rpcStats: rpcStats)
    }

    switch action {
    case .runClients:
      return clients
    case .invalidState(let error):
      for client in clients {
        client.shutdown()
      }
      throw error
    }
  }

  private func parseServerTarget(_ target: String) -> GRPCHTTP2Core.SocketAddress.IPv4? {
    guard let index = target.firstIndex(of: ":") else { return nil }

    let host = target[..<index]
    if let port = Int(target[target.index(after: index)...]) {
      return SocketAddress.IPv4(host: String(host), port: port)
    } else {
      return nil
    }
  }

  private func parseServerTargets(
    _ targets: [String]
  ) throws -> [GRPCHTTP2Core.SocketAddress.IPv4] {
    try targets.map { target in
      if let ipv4 = self.parseServerTarget(target) {
        return ipv4
      } else {
        throw RPCError(
          code: .invalidArgument,
          message: """
            Couldn't parse target '\(target)'. Must be in the format '<host>:<port>' for IPv4 \
            or '[<host>]:<port>' for IPv6.
            """
        )
      }
    }
  }

  private func makeClientStatsResponse(
    reset: Bool
  ) async throws -> Grpc_Testing_WorkerService.Method.RunClient.Output {
    let currentUsageStats = ClientStats()

    let stats = self.state.withLockedValue { state in
      state.collectClientStats(replaceWith: reset ? currentUsageStats : nil)
    }

    guard let (initialUsageStats, rpcStats) = stats else {
      throw RPCError(
        code: .notFound,
        message: "There are no initial client stats. Clients must be setup before calling 'mark'."
      )
    }

    let differences = currentUsageStats.difference(to: initialUsageStats)

    let requestResults = rpcStats.requestResultCount.map { (key, value) in
      return Grpc_Testing_RequestResultCount.with {
        $0.statusCode = Int32(key.rawValue)
        $0.count = value
      }
    }

    return Grpc_Testing_WorkerService.Method.RunClient.Output.with {
      $0.stats = Grpc_Testing_ClientStats.with {
        $0.timeElapsed = differences.time
        $0.timeSystem = differences.systemTime
        $0.timeUser = differences.userTime
        $0.requestResults = requestResults
        $0.latencies = Grpc_Testing_HistogramData.with {
          $0.bucket = rpcStats.latencyHistogram.buckets
          $0.minSeen = rpcStats.latencyHistogram.minSeen
          $0.maxSeen = rpcStats.latencyHistogram.maxSeen
          $0.sum = rpcStats.latencyHistogram.sum
          $0.sumOfSquares = rpcStats.latencyHistogram.sumOfSquares
          $0.count = rpcStats.latencyHistogram.countOfValuesSeen
        }
      }
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension BenchmarkClient.RPCType {
  init?(_ rpcType: Grpc_Testing_RpcType) {
    switch rpcType {
    case .unary:
      self = .unary
    case .streaming:
      self = .streaming
    default:
      return nil
    }
  }
}
