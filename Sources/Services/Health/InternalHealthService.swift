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

@available(macOS 15.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
internal final class InternalHealthService: Grpc_Health_V1_HealthServiceProtocol {
  private let state = InternalHealthService.State()

  func check(
    request: ServerRequest.Single<Grpc_Health_V1_HealthCheckRequest>
  ) async throws -> ServerResponse.Single<Grpc_Health_V1_HealthCheckResponse> {
    let service = request.message.service

    if let status = self.state.getCurrentStatus(ofService: service) {
      var response = Grpc_Health_V1_HealthCheckResponse()
      response.status = status

      return ServerResponse.Single(message: response)
    }

    throw RPCError(code: .notFound, message: "Requested service unknown.")
  }

  func watch(
    request: ServerRequest.Single<Grpc_Health_V1_HealthCheckRequest>
  ) async throws -> ServerResponse.Stream<Grpc_Health_V1_HealthCheckResponse> {
    let service = request.message.service
    let statuses = AsyncStream.makeStream(of: Grpc_Health_V1_HealthCheckResponse.ServingStatus.self)

    self.state.addContinuation(statuses.continuation, forService: service)

    return ServerResponse.Stream(
      of: Grpc_Health_V1_HealthCheckResponse.self
    ) { writer in
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
    ofService service: String
  ) {
    self.state.updateStatus(status, ofService: service)
  }
}

@available(macOS 15.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension InternalHealthService {
  private struct State: Sendable {
    private let lockedStorage = LockedValueBox([String: ServiceState]())

    fileprivate func getCurrentStatus(
      ofService service: String
    ) -> Grpc_Health_V1_HealthCheckResponse.ServingStatus? {
      return self.lockedStorage.withLockedValue { $0[service]?.currentStatus }
    }

    fileprivate func updateStatus(
      _ status: Grpc_Health_V1_HealthCheckResponse.ServingStatus,
      ofService service: String
    ) {
      self.lockedStorage.withLockedValue { storage in
        if storage[service] == nil {
          storage[service] = ServiceState(status: status)
        } else {
          storage[service]!.updateStatus(status)
        }
      }
    }

    fileprivate func addContinuation(
      _ continuation: AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>.Continuation,
      forService service: String
    ) {
      self.lockedStorage.withLockedValue { storage in
        storage[service, default: ServiceState(status: .serviceUnknown)]
          .addContinuation(continuation)
        continuation.yield(storage[service]!.currentStatus)
      }
    }
  }

  /// Encapsulates the current status of a service and the continuations of its "watch" streams.
  private struct ServiceState: Sendable {
    private(set) var currentStatus: Grpc_Health_V1_HealthCheckResponse.ServingStatus
    private var continuations:
      [AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>.Continuation]

    /// Updates the status and provides values to the streams.
    fileprivate mutating func updateStatus(
      _ status: Grpc_Health_V1_HealthCheckResponse.ServingStatus
    ) {
      if self.currentStatus != status {
        self.currentStatus = status

        for continuation in self.continuations {
          continuation.yield(status)
        }
      }
    }

    /// Adds a continuation for a stream of statuses.
    fileprivate mutating func addContinuation(
      _ continuation: AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>.Continuation
    ) {
      self.continuations.append(continuation)
    }

    fileprivate init(status: Grpc_Health_V1_HealthCheckResponse.ServingStatus) {
      self.currentStatus = status
      self.continuations = []
    }
  }
}
