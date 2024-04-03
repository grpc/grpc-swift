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
import NIOConcurrencyHelpers
import NIOCore

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class WorkerService: Grpc_Testing_WorkerService.ServiceProtocol, Sendable {
  private let state: NIOLockedValueBox<State>

  init() {
    let clientAndServer = State()
    self.state = NIOLockedValueBox(clientAndServer)
  }

  private struct State {
    var role: Role?

    enum Role {
      case client(GRPCClient)
      case server(ServerState)
    }

    struct ServerState {
      var server: GRPCServer
      var stats: ServerStats

      init(server: GRPCServer, stats: ServerStats) {
        self.server = server
        self.stats = stats
      }
    }

    init() {}

    init(role: Role) {
      self.role = role
    }

    var server: GRPCServer? {
      switch self.role {
      case let .server(serverState):
        return serverState.server
      case .client, .none:
        return nil
      }
    }

    mutating func serverStats(replaceWith newStats: ServerStats? = nil) -> ServerStats? {
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

    mutating func setupServer(server: GRPCServer, stats: ServerStats) throws {
      let serverState = State.ServerState(server: server, stats: stats)
      switch self.role {
      case .server(_):
        throw RPCError(code: .alreadyExists, message: "A server has already been set up.")

      case .client(_):
        throw RPCError(code: .failedPrecondition, message: "This worker has a client setup.")

      case .none:
        self.role = .server(serverState)
      }
    }
  }

  func quitWorker(
    request: ServerRequest.Single<Grpc_Testing_WorkerService.Method.QuitWorker.Input>
  ) async throws -> ServerResponse.Single<Grpc_Testing_WorkerService.Method.QuitWorker.Output> {

    let role = self.state.withLockedValue { state in
      defer { state.role = nil }
      return state.role
    }

    if let role = role {
      switch role {
      case .client(let client):
        client.close()
      case .server(let serverState):
        serverState.server.stopListening()
      }
    }

    return ServerResponse.Single(message: Grpc_Testing_WorkerService.Method.QuitWorker.Output())
  }

  func coreCount(
    request: ServerRequest.Single<Grpc_Testing_WorkerService.Method.CoreCount.Input>
  ) async throws -> ServerResponse.Single<Grpc_Testing_WorkerService.Method.CoreCount.Output> {
    let coreCount = System.coreCount
    return ServerResponse.Single(
      message: Grpc_Testing_WorkerService.Method.CoreCount.Output.with {
        $0.cores = Int32(coreCount)
      }
    )
  }

  func runServer(
    request: GRPCCore.ServerRequest.Stream<Grpc_Testing_WorkerService.Method.RunServer.Input>
  ) async throws
    -> GRPCCore.ServerResponse.Stream<Grpc_Testing_WorkerService.Method.RunServer.Output>
  {
    return ServerResponse.Stream { writer in
      try await withThrowingTaskGroup(of: Void.self) { group in
        for try await message in request.messages {
          switch message.argtype {
          case let .some(.setup(serverConfig)):
            let server = try await self.setupServer(serverConfig)
            group.addTask { try await server.run() }

          case let .some(.mark(mark)):
            let response = try await self.makeServerStatsResponse(reset: mark.reset)
            try await writer.write(response)

          case .none:
            ()
          }
        }

        try await group.next()
      }

      let server = self.state.withLockedValue { state in
        defer { state.role = nil }
        return state.server
      }

      server?.stopListening()
      return [:]
    }
  }

  func runClient(
    request: GRPCCore.ServerRequest.Stream<Grpc_Testing_WorkerService.Method.RunClient.Input>
  ) async throws
    -> GRPCCore.ServerResponse.Stream<Grpc_Testing_WorkerService.Method.RunClient.Output>
  {
    throw RPCError(code: .unimplemented, message: "This RPC has not been implemented yet.")
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension WorkerService {
  private func setupServer(_ config: Grpc_Testing_ServerConfig) async throws -> GRPCServer {
    let server = GRPCServer(transports: [], services: [BenchmarkService()])
    let stats = try await ServerStats()

    try self.state.withLockedValue { state in
      try state.setupServer(server: server, stats: stats)
    }

    return server
  }

  private func makeServerStatsResponse(
    reset: Bool
  ) async throws -> Grpc_Testing_WorkerService.Method.RunServer.Output {
    let currentStats = try await ServerStats()
    let initialStats = self.state.withLockedValue { state in
      return state.serverStats(replaceWith: reset ? currentStats : nil)
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
}
