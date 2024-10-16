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

/// A `ServerInterceptorTarget` describes to which RPCs a server interceptor should be applied.
///
/// You can configure a server interceptor to be applied to:
/// - all RPCs and services;
/// - requests directed only to specific services registered with your server; or
/// - requests directed only to specific methods (of a specific service).
///
/// - SeeAlso: ``ServerInterceptor`` for more information on server interceptors, and
///  ``ClientInterceptorTarget`` for the client-side version of this type.
public struct ServerInterceptorTarget: Sendable {
  internal enum Wrapped: Sendable {
    case allServices(interceptor: any ServerInterceptor)
    case serviceSpecific(interceptor: any ServerInterceptor, services: [String])
    case methodSpecific(interceptor: any ServerInterceptor, methods: [MethodDescriptor])
  }

  /// A target specifying an interceptor that applies to all RPCs across all services registered with this server.
  /// - Parameter interceptor: The interceptor to register with the server.
  /// - Returns: A ``ServerInterceptorTarget``.
  public static func allServices(
    interceptor: any ServerInterceptor
  ) -> Self {
    Self(wrapped: .allServices(interceptor: interceptor))
  }

  /// A target specifying an interceptor that applies to RPCs directed only to the specified services.
  /// - Parameters:
  ///   - interceptor: The interceptor to register with the server.
  ///   - services: The list of service names for which this interceptor should intercept RPCs.
  /// - Returns: A ``ServerInterceptorTarget``.
  public static func serviceSpecific(
    interceptor: any ServerInterceptor,
    services: [String]
  ) -> Self {
    Self(
      wrapped: .serviceSpecific(
        interceptor: interceptor,
        services: services
      )
    )
  }

  /// A target specifying an interceptor that applies to RPCs directed only to the specified service methods.
  /// - Parameters:
  ///   - interceptor: The interceptor to register with the server.
  ///   - services: The list of method descriptors for which this interceptor should intercept RPCs.
  /// - Returns: A ``ServerInterceptorTarget``.
  public static func methodSpecific(
    interceptor: any ServerInterceptor,
    methods: [MethodDescriptor]
  ) -> Self {
    Self(
      wrapped: .methodSpecific(
        interceptor: interceptor,
        methods: methods
      )
    )
  }

  private let wrapped: Wrapped

  private init(wrapped: Wrapped) {
    self.wrapped = wrapped
  }

  /// Get the ``ServerInterceptor`` associated with this ``ServerInterceptorTarget``.
  public var interceptor: any ServerInterceptor {
    switch self.wrapped {
    case .allServices(let interceptor):
      return interceptor
    case .serviceSpecific(let interceptor, _):
      return interceptor
    case .methodSpecific(let interceptor, _):
      return interceptor
    }
  }

  /// Returns whether this ``ServerInterceptorTarget`` applies to the given `descriptor`.
  /// - Parameter descriptor: A ``MethodDescriptor`` for which to test whether this interceptor applies.
  /// - Returns: `true` if this interceptor applies to the given `descriptor`, or `false` otherwise.
  public func applies(to descriptor: MethodDescriptor) -> Bool {
    switch self.wrapped {
    case .allServices:
      return true
    case .serviceSpecific(_, let services):
      return services.contains(descriptor.service)
    case .methodSpecific(_, let methods):
      return methods.contains(descriptor)
    }
  }
}
