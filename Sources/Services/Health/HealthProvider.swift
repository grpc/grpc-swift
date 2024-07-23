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

/// Provides handlers to interact with a Health service.
@available(macOS 15.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct HealthProvider: Sendable {
  private let healthService: HealthService

  /// Updates the status of a service in the Health service.
  public func updateService(
    descriptor: ServiceDescriptor,
    status: ServingStatus
  ) throws {
    try self.healthService.service.updateService(
      descriptor: descriptor,
      status: Grpc_Health_V1_HealthCheckResponse.ServingStatus(from: status)
    )
  }

  /// Constructs a new ``HealthProvider``.
  ///
  /// - Parameters:
  ///   - healthService: The Health service to handle.
  internal init(healthService: HealthService) {
    self.healthService = healthService
  }
}

extension Grpc_Health_V1_HealthCheckResponse.ServingStatus {
  /// Constructs a new ``Grpc_Health_V1_HealthCheckResponse.ServingStatus`` from ``ServingStatus``.
  ///
  /// - Parameters:
  ///   - from: The base status.
  package init(from status: ServingStatus) {
    switch status.value {
    case .serving: self = .serving
    case .notServing: self = .notServing
    }
  }
}
