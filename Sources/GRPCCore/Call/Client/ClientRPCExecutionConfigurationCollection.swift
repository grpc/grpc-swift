/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)

/// A collection of ``ClientRPCExecutionConfiguration``s, mapped to specific methods or services.
///
/// When creating a new instance, you must provide a default configuration to be used when getting
/// a configuration for a method that has not been given a specific override.
/// Use ``setDefaultConfiguration(_:forService:)`` to set a specific override for a whole
/// service.
///
/// Use the subscript to get and set configurations for methods.
public struct ClientRPCExecutionConfigurationCollection: Sendable, Hashable {
  private var elements: [MethodDescriptor: ClientRPCExecutionConfiguration]
  private let defaultConfiguration: ClientRPCExecutionConfiguration

  public init(
    defaultConfiguration: ClientRPCExecutionConfiguration = ClientRPCExecutionConfiguration(
      executionPolicy: nil,
      timeout: nil
    )
  ) {
    self.elements = [:]
    self.defaultConfiguration = defaultConfiguration
  }

  public subscript(_ descriptor: MethodDescriptor) -> ClientRPCExecutionConfiguration {
    get {
      if let methodLevelOverride = self.elements[descriptor] {
        return methodLevelOverride
      }
      var serviceLevelDescriptor = descriptor
      serviceLevelDescriptor.method = ""
      return self.elements[serviceLevelDescriptor, default: self.defaultConfiguration]
    }

    set {
      precondition(
        !descriptor.service.isEmpty,
        "Method descriptor's service cannot be empty."
      )

      self.elements[descriptor] = newValue
    }
  }

  /// Set a default configuration for a service.
  ///
  /// If getting a configuration for a method that's part of a service, and the method itself doesn't have an
  /// override, then this configuration will be used instead of the default configuration passed when creating
  /// this instance of ``ClientRPCExecutionConfigurationCollection``.
  ///
  /// - Parameters:
  ///   - configuration: The default configuration for the service.
  ///   - service: The name of the service for which this override applies.
  public mutating func setDefaultConfiguration(
    _ configuration: ClientRPCExecutionConfiguration,
    forService service: String
  ) {
    self[MethodDescriptor(service: service, method: "")] = configuration
  }
}
