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
/// `Health` initializes a new ``Health/Service-swift.struct`` and ``Health/Provider-swift.struct``.
/// - `Health.Service` implements the Health service from the `grpc.health.v1` package and can be registered with a server
/// like any other service.
/// - `Health.Provider` provides status updates to `Health.Service`. `Health.Service` doesn't know about the other
/// services running on a server so it must be provided with status updates via `Health.Provider`. To make specifying the service
/// being updated easier, the generated code for services includes an extension to `ServiceDescriptor`.
///
/// The following shows an example of initializing a Health service and updating the status of the `Foo` service in the `bar` package.
///
/// ```swift
/// let health = Health()
/// let server = GRPCServer(
///   transport: transport,
///   services: [health.service, FooService()]
/// )
///
/// health.provider.updateStatus(
///   .serving,
///   forService: .bar_Foo
/// )
/// ```
@available(macOS 15.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct Health: Sendable {
  /// An implementation of the `grpc.health.v1.Health` service.
  public let service: Health.Service

  /// Provides status updates to the Health service.
  public let provider: Health.Provider

  /// Constructs a new ``Health``, initializing a ``Health/Service-swift.struct`` and a
  /// ``Health/Provider-swift.struct``.
  public init() {
    let healthService = HealthService()

    self.service = Health.Service(healthService: healthService)
    self.provider = Health.Provider(healthService: healthService)
  }
}

@available(macOS 15.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Health {
  /// An implementation of the `grpc.health.v1.Health` service.
  public struct Service: RegistrableRPCService, Sendable {
    private let healthService: HealthService

    public func registerMethods(with router: inout RPCRouter) {
      self.healthService.registerMethods(with: &router)
    }

    fileprivate init(healthService: HealthService) {
      self.healthService = healthService
    }
  }

  /// Provides status updates to ``Health/Service-swift.struct``.
  public struct Provider: Sendable {
    private let healthService: HealthService

    /// Updates the status of a service.
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

    /// Updates the status of a service.
    ///
    /// - Parameters:
    ///   - status: The status of the service.
    ///   - service: The fully qualified service name in the format:
    ///     - "package.service": if the service is part of a package. For example, "helloworld.Greeter".
    ///     - "service": if the service is not part of a package. For example, "Greeter".
    public func updateStatus(
      _ status: ServingStatus,
      forService service: String
    ) {
      self.healthService.updateStatus(
        Grpc_Health_V1_HealthCheckResponse.ServingStatus(status),
        forService: service
      )
    }

    fileprivate init(healthService: HealthService) {
      self.healthService = healthService
    }
  }
}

extension Grpc_Health_V1_HealthCheckResponse.ServingStatus {
  package init(_ status: ServingStatus) {
    switch status.value {
    case .serving:
      self = .serving
    case .notServing:
      self = .notServing
    }
  }
}
