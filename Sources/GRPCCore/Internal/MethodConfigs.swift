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

/// A collection of ``MethodConfig``s, mapped to specific methods or services.
///
/// When creating a new instance, no overrides and no default will be set for using when getting
/// a configuration for a method that has not been given a specific override.
/// Use ``setDefaultConfig(_:forService:)`` to set a specific override for a whole
/// service, or set a default configuration for all methods by calling ``setDefaultConfig(_:)``.
///
/// Use the subscript to get and set configurations for specific methods.
package struct MethodConfigs: Sendable, Hashable {
  private var elements: [MethodConfig.Name: MethodConfig]

  /// Create a new ``_MethodConfigs``.
  ///
  /// - Parameter serviceConfig: The configuration to read ``MethodConfig`` from.
  package init(serviceConfig: ServiceConfig = ServiceConfig()) {
    self.elements = [:]

    for configuration in serviceConfig.methodConfig {
      for name in configuration.names {
        self.elements[name] = configuration
      }
    }
  }

  /// Get or set the corresponding ``MethodConfig`` for the given ``MethodDescriptor``.
  ///
  /// Configuration is hierarchical and can be set per-method, per-service
  /// (``setDefaultConfig(_:forService:)``) and globally (``setDefaultConfig(_:)``).
  /// This subscript sets the per-method configuration but retrieves a configuration respecting
  /// the hierarchy. If no per-method configuration is present, the per-service configuration is
  /// checked and returned if present. If the per-service configuration isn't present then the
  /// global configuration is returned, if present.
  ///
  /// - Parameters:
  ///  - descriptor: The ``MethodDescriptor`` for which to get or set a ``MethodConfig``.
  package subscript(_ descriptor: MethodDescriptor) -> MethodConfig? {
    get {
      var name = MethodConfig.Name(
        service: descriptor.service.fullyQualifiedService,
        method: descriptor.method
      )

      if let configuration = self.elements[name] {
        return configuration
      }

      // Check if the config is set at the service level by clearing the method.
      name.method = ""

      if let configuration = self.elements[name] {
        return configuration
      }

      // Check if the config is set at the global level by clearing the service and method.
      name.service = ""
      return self.elements[name]
    }

    set {
      let name = MethodConfig.Name(
        service: descriptor.service.fullyQualifiedService,
        method: descriptor.method
      )
      self.elements[name] = newValue
    }
  }

  /// Set a default configuration for all methods that have no overrides.
  ///
  /// - Parameter config: The default configuration.
  package mutating func setDefaultConfig(_ config: MethodConfig?) {
    let name = MethodConfig.Name(service: "", method: "")
    self.elements[name] = config
  }

  /// Set a default configuration for a service.
  ///
  /// If getting a configuration for a method that's part of a service, and the method itself doesn't have an
  /// override, then this configuration will be used instead of the default configuration passed when creating
  /// this instance of ``MethodConfigs``.
  ///
  /// - Parameters:
  ///   - config: The default configuration for the service.
  ///   - service: The name of the service for which this override applies.
  package mutating func setDefaultConfig(
    _ config: MethodConfig?,
    forService service: String
  ) {
    let name = MethodConfig.Name(service: "", method: "")
    self.elements[name] = config
  }
}
