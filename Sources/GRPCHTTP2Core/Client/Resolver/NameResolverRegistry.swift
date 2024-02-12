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

/// A registry for name resolver factories.
///
/// The registry provides name resolvers for resolvable targets. You can control which name
/// resolvers are available by registering and removing resolvers by type. The following code
/// demonstrates how to create a registry, add and remove resolver factories, and create a resolver.
///
/// ```swift
/// // Create a new resolver registry with the default resolvers.
/// var registry = NameResolverRegistry.defaults
///
/// // Register a custom resolver, the registry can now resolve targets of
/// // type `CustomResolver.ResolvableTarget`.
/// registry.registerFactory(CustomResolver())
///
/// // Remove the Unix Domain Socket and VSOCK resolvers, if they exist.
/// registry.removeFactory(ofType: NameResolvers.UnixDomainSocket.self)
/// registry.removeFactory(ofType: NameResolvers.VSOCK.self)
///
/// // Resolve an IPv4 target
/// if let resolver = registry.makeResolver(for: .ipv4(host: "localhost", port: 80)) {
///   // ...
/// }
/// ```
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct NameResolverRegistry {
  private enum Factory {
    case other(any NameResolverFactory)

    init(_ factory: some NameResolverFactory) {
      self = .other(factory)
    }

    func makeResolverIfCompatible<Target: ResolvableTarget>(_ target: Target) -> NameResolver? {
      switch self {
      case .other(let factory):
        return factory.makeResolverIfCompatible(target)
      }
    }

    func hasTarget<Target: ResolvableTarget>(_ target: Target) -> Bool {
      switch self {
      case .other(let factory):
        return factory.isCompatible(withTarget: target)
      }
    }

    func `is`<Factory: NameResolverFactory>(ofType factoryType: Factory.Type) -> Bool {
      switch self {
      case .other(let factory):
        return type(of: factory) == factoryType
      }
    }
  }

  private var factories: [Factory]

  /// Creates a new name resolver registry with no resolve factories.
  public init() {
    self.factories = []
  }

  /// Returns a new name resolver registry with the default factories registered.
  public static var defaults: Self {
    return NameResolverRegistry()
  }

  /// The number of resolver factories in the registry.
  public var count: Int {
    return self.factories.count
  }

  /// Whether there are no resolver factories in the registry.
  public var isEmpty: Bool {
    return self.factories.isEmpty
  }

  /// Registers a new name resolver factory.
  ///
  /// Any factories of the same type are removed prior to inserting the factory.
  ///
  /// - Parameter factory: The factory to register.
  public mutating func registerFactory<Factory: NameResolverFactory>(_ factory: Factory) {
    self.removeFactory(ofType: Factory.self)
    self.factories.append(Self.Factory(factory))
  }

  /// Removes any factories which have the given type
  ///
  /// - Parameter type: The type of factory to remove.
  /// - Returns: Whether a factory was removed.
  @discardableResult
  public mutating func removeFactory<Factory: NameResolverFactory>(
    ofType type: Factory.Type
  ) -> Bool {
    let factoryCount = self.factories.count
    self.factories.removeAll {
      $0.is(ofType: Factory.self)
    }
    return self.factories.count < factoryCount
  }

  /// Returns whether the registry contains a factory of the given type.
  ///
  /// - Parameter type: The type of factory to look for.
  /// - Returns: Whether the registry contained the factory of the given type.
  public func containsFactory<Factory: NameResolverFactory>(ofType type: Factory.Type) -> Bool {
    self.factories.contains {
      $0.is(ofType: Factory.self)
    }
  }

  /// Returns whether the registry contains a factory capable of resolving the given target.
  ///
  /// - Parameter target:
  /// - Returns: Whether the registry contains a resolve capable of resolving the target.
  public func containsFactory(capableOfResolving target: some ResolvableTarget) -> Bool {
    self.factories.contains { $0.hasTarget(target) }
  }

  /// Makes a ``NameResolver`` for the target, if a suitable factory exists.
  ///
  /// If multiple factories exist which are capable of resolving the target then the first
  /// is used.
  ///
  /// - Parameter target: The target to make a resolver for.
  /// - Returns: The resolver, or `nil` if no factory could make a resolver for the target.
  public func makeResolver(for target: some ResolvableTarget) -> NameResolver? {
    for factory in self.factories {
      if let resolver = factory.makeResolverIfCompatible(target) {
        return resolver
      }
    }
    return nil
  }
}
