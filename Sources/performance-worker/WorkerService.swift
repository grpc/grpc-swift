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
      case server(GRPCServer)
    }

    init() {}

    init(role: Role) {
      self.role = role
    }

    init(server: GRPCServer) {
      self.role = .server(server)
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
    throw RPCError(code: .unimplemented, message: "This RPC has not been implemented yet.")
  }

  func runClient(
    request: GRPCCore.ServerRequest.Stream<Grpc_Testing_WorkerService.Method.RunClient.Input>
  ) async throws
    -> GRPCCore.ServerResponse.Stream<Grpc_Testing_WorkerService.Method.RunClient.Output>
  {
    throw RPCError(code: .unimplemented, message: "This RPC has not been implemented yet.")
  }
}
