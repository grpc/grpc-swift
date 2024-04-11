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

// TODO: when swift(>=5.9), use 'package' access level

/// A collection of ``MethodConfig``s, mapped to specific methods or services.
///
/// When creating a new instance, no overrides and no default will be set for using when getting
/// a configuration for a method that has not been given a specific override.
/// Use ``setDefaultConfiguration(_:forService:)`` to set a specific override for a whole
/// service, or set a default configuration for all methods by calling ``setDefaultConfiguration(_:)``.
///
/// Use the subscript to get and set configurations for specific methods.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct _MethodConfigs: Sendable, Hashable {
  private var elements: [MethodConfig.Name: MethodConfig]

  /// Create a new ``_MethodConfigs``.
  ///
  /// - Parameter serviceConfig: The configuration to read ``MethodConfig`` from.
  public init(serviceConfig: ServiceConfig = ServiceConfig()) {
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
  /// (``setDefaultConfiguration(_:forService:)``) and globally (``setDefaultConfiguration(_:)``).
  /// This subscript sets the per-method configuration but retrieves a configuration respecting
  /// the hierarchy. If no per-method configuration is present, the per-service configuration is
  /// checked and returned if present. If the per-service configuration isn't present then the
  /// global configuration is returned, if present.
  ///
  /// - Parameters:
  ///  - descriptor: The ``MethodDescriptor`` for which to get or set a ``MethodConfig``.
  public subscript(_ descriptor: MethodDescriptor) -> MethodConfig? {
    get {
      var name = MethodConfig.Name(service: descriptor.service, method: descriptor.method)

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
      let name = MethodConfig.Name(service: descriptor.service, method: descriptor.method)
      self.elements[name] = newValue
    }
  }

  /// Set a default configuration for all methods that have no overrides.
  ///
  /// - Parameter configuration: The default configuration.
  public mutating func setDefaultConfiguration(_ configuration: MethodConfig?) {
    let name = MethodConfig.Name(service: "", method: "")
    self.elements[name] = configuration
  }

  /// Set a default configuration for a service.
  ///
  /// If getting a configuration for a method that's part of a service, and the method itself doesn't have an
  /// override, then this configuration will be used instead of the default configuration passed when creating
  /// this instance of ``MethodConfigs``.
  ///
  /// - Parameters:
  ///   - configuration: The default configuration for the service.
  ///   - service: The name of the service for which this override applies.
  public mutating func setDefaultConfiguration(
    _ configuration: MethodConfig?,
    forService service: String
  ) {
    let name = MethodConfig.Name(service: "", method: "")
    self.elements[name] = configuration
  }
}
