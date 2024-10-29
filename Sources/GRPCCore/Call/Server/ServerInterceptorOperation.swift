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

/// A `ServerInterceptorOperation` describes to which RPCs a server interceptor should be applied.
///
/// You can configure a server interceptor to be applied to:
/// - all RPCs and services;
/// - requests directed only to specific services registered with your server; or
/// - requests directed only to specific methods (of a specific service).
///
/// - SeeAlso: ``ServerInterceptor`` for more information on server interceptors, and
///  ``ClientInterceptorOperation`` for the client-side version of this type.
public struct ServerInterceptorOperation: Sendable {
  internal enum Wrapped: Sendable {
    case allServices(interceptor: any ServerInterceptor)
    case serviceSpecific(interceptor: any ServerInterceptor, services: [String])
    case methodSpecific(interceptor: any ServerInterceptor, methods: [MethodDescriptor])
  }

  /// An operation specifying an interceptor that applies to all RPCs across all services will be registered with this server.
  /// - Parameter interceptor: The interceptor to register with the server.
  /// - Returns: A ``ServerInterceptorOperation``.
  public static func applyToAllServices(
    _ interceptor: any ServerInterceptor
  ) -> Self {
    Self(wrapped: .allServices(interceptor: interceptor))
  }

  /// An operation specifying an interceptor that will be applied only to RPCs directed to the specified services.
  /// - Parameters:
  ///   - interceptor: The interceptor to register with the server.
  ///   - services: The list of service names for which this interceptor should intercept RPCs.
  /// - Returns: A ``ServerInterceptorOperation``.
  public static func apply(
    _ interceptor: any ServerInterceptor,
    onlyToServices services: [String]
  ) -> Self {
    Self(
      wrapped: .serviceSpecific(
        interceptor: interceptor,
        services: services
      )
    )
  }

  /// An operation specifying an interceptor that will be applied only to RPCs directed to the specified service methods.
  /// - Parameters:
  ///   - interceptor: The interceptor to register with the server.
  ///   - services: The list of method descriptors for which this interceptor should intercept RPCs.
  /// - Returns: A ``ServerInterceptorOperation``.
  public static func apply(
    _ interceptor: any ServerInterceptor,
    onlyToMethods methods: [MethodDescriptor]
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

  /// Get the ``ServerInterceptor`` associated with this ``ServerInterceptorOperation``.
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

  /// Returns whether this ``ServerInterceptorOperation`` applies to the given `descriptor`.
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
