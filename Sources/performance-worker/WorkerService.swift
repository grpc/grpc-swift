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
    var initialStats: ServerStats?

    enum Role {
      case client(GRPCClient)
      case server(GRPCServer)
    }

    init() {}

    init(role: Role) async throws {
      self.role = role
      self.initialStats = try await ServerStats()
    }

    init(server: GRPCServer) async throws {
      self.role = .server(server)
      self.initialStats = try await ServerStats()
    }

    init(client: GRPCClient) {
      self.role = .client(client)
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
      case .server(let server):
        server.stopListening()
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
      for try await message in request.messages {
        switch message.argtype {
        case let .some(.setup(serverConfig)):
          try await self.serverSetup(serverConfig)
        case let .some(.mark(mark)):
          let response = try await self.makeStatsResponse(for: mark)
          try await writer.write(response)
        case .none:
          ()
        }
        throw RPCError(code: .unavailable, message: "This RPC has not been implemented yet.")
      }
      try self.state.withLockedValue {
        switch $0.role {
        case .server(let server):
          server.stopListening()
        default:
          throw RPCError(code: .unavailable, message: "There is no benchmark server.")
        }
      }
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
  private func serverSetup(_ config: Grpc_Testing_ServerConfig) async throws {
    try self.state.withLockedValue { state in
      switch state.role {
      case .server(_):
        throw RPCError(code: .alreadyExists, message: "A server has been previously set up.")
      case .client(_):
        throw RPCError(code: .failedPrecondition, message: "This worker has a client set up.")
      default:
        ()
      }
    }
    // The asynchronous function 'run()' can't be called inside the synchronous
    // closure passed to 'withLockedValue'.
    let server = GRPCServer(transports: [], services: [BenchmarkService()])
    try await server.run()
  }

  private func makeStatsResponse(
    for mark: Grpc_Testing_Mark
  ) async throws -> Grpc_Testing_WorkerService.Method.RunServer.Output {
    let currentStats = try await ServerStats()
    let initialStats = self.state.withLockedValue { state in
      defer {
        if mark.reset {
          state.initialStats = currentStats
        }
      }
      return state.initialStats
    }

    guard let initialStats = initialStats else {
      throw RPCError(code: .notFound, message: "There are no initial server stats.")
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
