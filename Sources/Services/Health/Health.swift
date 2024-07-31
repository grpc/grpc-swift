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

/// ``Health`` is gRPC’s mechanism for checking whether a server is able to handle RPCs. Its semantics are documented in
/// https://github.com/grpc/grpc/blob/master/doc/health-checking.md.
///
/// `Health` initializes a new `Health.Service` and a `Health.Provider`.
/// - `Health.Service` is a registerable RPC service to probe whether a server is able to handle RPCs.
/// - `Health.Provider` provides handlers to interact with `Health.Service`.
@available(macOS 15.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct Health: Sendable {
  /// A registerable RPC service to probe whether a server is able to handle RPCs.
  public let service: Health.Service

  /// Provides handlers to interact with the coupled Health service.
  public let provider: Health.Provider

  /// Constructs a new `Health`, coupling a `Health.Service` and a `Health.Provider`.
  public init() {
    let healthService = HealthService()

    self.service = Health.Service(healthService: healthService)
    self.provider = Health.Provider(healthService: healthService)
  }
}

@available(macOS 15.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Health {
  /// A registerable RPC service to probe whether a server is able to handle RPCs.
  public struct Service: RegistrableRPCService, Sendable {
    private let healthService: HealthService

    public func registerMethods(with router: inout RPCRouter) {
      self.healthService.registerMethods(with: &router)
    }

    fileprivate init(healthService: HealthService) {
      self.healthService = healthService
    }
  }

  /// Provides handlers to interact with a Health service.
  public struct Provider: Sendable {
    private let healthService: HealthService

    /// Updates the status of a service in the Health service.
    ///
    /// - Parameters:
    ///   - status: The status of the service.
    ///   - service: The description of the service.
    public func updateStatus(
      _ status: ServingStatus,
      forService service: ServiceDescriptor
    ) {
      self.healthService.updateStatus(
        Grpc_Health_V1_HealthCheckResponse.ServingStatus(status),
        forService: service.fullyQualifiedService
      )
    }

    fileprivate init(healthService: HealthService) {
      self.healthService = healthService
    }
  }
}

extension Grpc_Health_V1_HealthCheckResponse.ServingStatus {
  /// Constructs a new ``Grpc_Health_V1_HealthCheckResponse/ServingStatus`` from ``ServingStatus``.
  ///
  /// - Parameters:
  ///   - status: The base status.
  package init(_ status: ServingStatus) {
    switch status.value {
    case .serving:
      self = .serving
    case .notServing:
      self = .notServing
    }
  }
}
