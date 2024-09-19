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

internal import GRPCCore
private import Synchronization

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
internal struct HealthService: Grpc_Health_V1_HealthServiceProtocol {
  private let state = HealthService.State()

  func check(
    request: ServerRequest.Single<Grpc_Health_V1_HealthCheckRequest>,
    context: ServerContext
  ) async throws -> ServerResponse.Single<Grpc_Health_V1_HealthCheckResponse> {
    let service = request.message.service

    guard let status = self.state.currentStatus(ofService: service) else {
      throw RPCError(code: .notFound, message: "Requested service unknown.")
    }

    var response = Grpc_Health_V1_HealthCheckResponse()
    response.status = status

    return ServerResponse.Single(message: response)
  }

  func watch(
    request: ServerRequest.Single<Grpc_Health_V1_HealthCheckRequest>,
    context: ServerContext
  ) async -> ServerResponse.Stream<Grpc_Health_V1_HealthCheckResponse> {
    let service = request.message.service
    let statuses = AsyncStream.makeStream(of: Grpc_Health_V1_HealthCheckResponse.ServingStatus.self)

    self.state.addContinuation(statuses.continuation, forService: service)

    return ServerResponse.Stream(of: Grpc_Health_V1_HealthCheckResponse.self) { writer in
      var response = Grpc_Health_V1_HealthCheckResponse()

      for await status in statuses.stream {
        response.status = status
        try await writer.write(response)
      }

      return [:]
    }
  }

  func updateStatus(
    _ status: Grpc_Health_V1_HealthCheckResponse.ServingStatus,
    forService service: String
  ) {
    self.state.updateStatus(status, forService: service)
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HealthService {
  private final class State: Sendable {
    // The state of each service keyed by the fully qualified service name.
    private let lockedStorage = Mutex([String: ServiceState]())

    fileprivate func currentStatus(
      ofService service: String
    ) -> Grpc_Health_V1_HealthCheckResponse.ServingStatus? {
      return self.lockedStorage.withLock { $0[service]?.currentStatus }
    }

    fileprivate func updateStatus(
      _ status: Grpc_Health_V1_HealthCheckResponse.ServingStatus,
      forService service: String
    ) {
      self.lockedStorage.withLock { storage in
        storage[service, default: ServiceState(status: status)].updateStatus(status)
      }
    }

    fileprivate func addContinuation(
      _ continuation: AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>.Continuation,
      forService service: String
    ) {
      self.lockedStorage.withLock { storage in
        storage[service, default: ServiceState(status: .serviceUnknown)]
          .addContinuation(continuation)
      }
    }
  }

  // Encapsulates the current status of a service and the continuations of its watch streams.
  private struct ServiceState: Sendable {
    private(set) var currentStatus: Grpc_Health_V1_HealthCheckResponse.ServingStatus
    private var continuations:
      [AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>.Continuation]

    fileprivate mutating func updateStatus(
      _ status: Grpc_Health_V1_HealthCheckResponse.ServingStatus
    ) {
      guard status != self.currentStatus else {
        return
      }

      self.currentStatus = status

      for continuation in self.continuations {
        continuation.yield(status)
      }
    }

    fileprivate mutating func addContinuation(
      _ continuation: AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>.Continuation
    ) {
      self.continuations.append(continuation)
      continuation.yield(self.currentStatus)
    }

    fileprivate init(status: Grpc_Health_V1_HealthCheckResponse.ServingStatus = .unknown) {
      self.currentStatus = status
      self.continuations = []
    }
  }
}
