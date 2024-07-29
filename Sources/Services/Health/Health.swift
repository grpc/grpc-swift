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

/// A coupled Health service and provider.
@available(macOS 15.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct Health: Sendable {
  private let internalHealthService = InternalHealthService()

  /// A registerable RPC service to probe whether a server is able to handle RPCs.
  public let service: Health.Service

  /// Provides handlers to interact with the coupled Health service.
  public let provider: Provider

  /// Constructs a new ``Health``, coupling a ``Health.Service`` and a ``Health.Provider``.
  public init() {
    self.service = Health.Service(internalHealthService: self.internalHealthService)
    self.provider = Health.Provider(internalHealthService: self.internalHealthService)
  }
}

@available(macOS 15.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Health {
  /// A registerable RPC service to probe whether a server is able to handle RPCs.
  public struct Service: RegistrableRPCService, Sendable {
    private let internalHealthService: InternalHealthService

    public func registerMethods(with router: inout RPCRouter) {
      self.internalHealthService.registerMethods(with: &router)
    }

    fileprivate init(internalHealthService: InternalHealthService) {
      self.internalHealthService = internalHealthService
    }
  }

  /// Provides handlers to interact with a Health service.
  public struct Provider: Sendable {
    private let internalHealthService: InternalHealthService

    /// Updates the status of a service in the Health service.
    public func updateStatus(
      _ status: ServingStatus,
      ofService service: ServiceDescriptor
    ) {
      self.internalHealthService.updateStatus(
        Grpc_Health_V1_HealthCheckResponse.ServingStatus(status),
        ofService: service.fullyQualifiedService
      )
    }

    fileprivate init(internalHealthService: InternalHealthService) {
      self.internalHealthService = internalHealthService
    }
  }
}

extension Grpc_Health_V1_HealthCheckResponse.ServingStatus {
  /// Constructs a new ``Grpc_Health_V1_HealthCheckResponse.ServingStatus`` from ``ServingStatus``.
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
