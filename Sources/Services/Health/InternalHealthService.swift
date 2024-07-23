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
  private let lockedStorage = LockedValueBox([String: StatusAndContinuations]())

  /// Creates a response with `status` and writes that response to a stream.
  private func writeResponseToStream(
    writer: RPCWriter<Grpc_Health_V1_HealthCheckResponse>,
    status: Grpc_Health_V1_HealthCheckResponse.ServingStatus
  ) async throws {
    var response = Grpc_Health_V1_HealthCheckResponse()
    response.status = status

    try await writer.write(response)
  }

  func check(
    request: ServerRequest.Single<Grpc_Health_V1_HealthCheckRequest>
  ) async throws -> ServerResponse.Single<Grpc_Health_V1_HealthCheckResponse> {
    let service = request.message.service

    if let statusAndContinuations = self.lockedStorage.withLockedValue({ $0[service] }) {
      var response = Grpc_Health_V1_HealthCheckResponse()
      response.status = statusAndContinuations.status

      return ServerResponse.Single(message: response)
    }

    return ServerResponse.Single(
      error: RPCError(status: Status(code: .notFound, message: "Requested service unknown."))!
    )
  }

  func watch(
    request: ServerRequest.Single<Grpc_Health_V1_HealthCheckRequest>
  ) async throws -> ServerResponse.Stream<Grpc_Health_V1_HealthCheckResponse> {
    let service = request.message.service

    let statusStream = AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus> {
      continuation in

      self.lockedStorage.withLockedValue { storage in
        if storage[service] == nil {
          storage[service] = StatusAndContinuations(status: .serviceUnknown)
        }

        storage[service]!.addContinuation(continuation)
      }
    }

    return ServerResponse.Stream(
      of: Grpc_Health_V1_HealthCheckResponse.self
    ) { writer in
      try await self.writeResponseToStream(
        writer: writer,
        status: self.lockedStorage.withLockedValue { storage in
          assert(storage[service] != nil)

          return storage[service]!.status
        }
      )

      for await status in statusStream {
        try await self.writeResponseToStream(writer: writer, status: status)
      }

      return Metadata()
    }
  }

  /// Updates the status of a service in the storage.
  func updateService(
    descriptor: ServiceDescriptor,
    status: Grpc_Health_V1_HealthCheckResponse.ServingStatus
  ) throws {
    try self.lockedStorage.withLockedValue { storage in
      if storage[descriptor.fullyQualifiedService] == nil {
        storage[descriptor.fullyQualifiedService] = StatusAndContinuations(status: status)
      } else {
        try storage[descriptor.fullyQualifiedService]!.update(status)
      }
    }
  }

  /// The status of a service, and the continuation of its "watch" streams.
  private struct StatusAndContinuations {
    private(set) var status: Grpc_Health_V1_HealthCheckResponse.ServingStatus
    private var continuations = [
      AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>.Continuation
    ]()

    /// Updates the status and provides values to the streams.
    fileprivate mutating func update(
      _ status: Grpc_Health_V1_HealthCheckResponse.ServingStatus
    ) throws {
      self.status = status

      for continuation in self.continuations {
        continuation.yield(status)
      }
    }

    /// Adds a continuation for a stream of statuses.
    fileprivate mutating func addContinuation(
      _ continuation: AsyncStream<Grpc_Health_V1_HealthCheckResponse.ServingStatus>.Continuation
    ) {
      self.continuations.append(continuation)
    }

    fileprivate init(status: Grpc_Health_V1_HealthCheckResponse.ServingStatus) {
      self.status = status
    }
  }
}
