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

/// A `ServerInterceptorPipelineOperation` describes to which RPCs a server interceptor should be applied.
///
/// You can configure a server interceptor to be applied to:
/// - all RPCs and services;
/// - requests directed only to specific services registered with your server; or
/// - requests directed only to specific methods (of a specific service).
///
/// - SeeAlso: ``ServerInterceptor`` for more information on server interceptors.
public struct ServerInterceptorPipelineOperation: Sendable {
  /// The subject of a ``ServerInterceptorPipelineOperation``.
  /// The subject of an interceptor can either be all services and methods, only specific services, or only specific methods.
  public struct Subject: Sendable {
    internal enum Wrapped: Sendable {
      case all
      case services(Set<ServiceDescriptor>)
      case methods(Set<MethodDescriptor>)
    }

    private let wrapped: Wrapped

    /// An operation subject specifying an interceptor that applies to all RPCs across all services will be registered with this server.
    public static var all: Self { .init(wrapped: .all) }

    /// An operation subject specifying an interceptor that will be applied only to RPCs directed to the specified services.
    /// - Parameters:
    ///   - services: The list of service names for which this interceptor should intercept RPCs.
    /// - Returns: A ``ServerInterceptorPipelineOperation``.
    public static func services(_ services: Set<ServiceDescriptor>) -> Self {
      Self(wrapped: .services(services))
    }

    /// An operation subject specifying an interceptor that will be applied only to RPCs directed to the specified service methods.
    /// - Parameters:
    ///   - methods: The list of method descriptors for which this interceptor should intercept RPCs.
    /// - Returns: A ``ServerInterceptorPipelineOperation``.
    public static func methods(_ methods: Set<MethodDescriptor>) -> Self {
      Self(wrapped: .methods(methods))
    }

    @usableFromInline
    internal func applies(to descriptor: MethodDescriptor) -> Bool {
      switch self.wrapped {
      case .all:
        return true

      case .services(let services):
        return services.map({ $0.fullyQualifiedService }).contains(descriptor.service)

      case .methods(let methods):
        return methods.contains(descriptor)
      }
    }
  }

  /// The interceptor specified for this operation.
  public let interceptor: any ServerInterceptor

  @usableFromInline
  internal let subject: Subject

  private init(interceptor: any ServerInterceptor, appliesTo: Subject) {
    self.interceptor = interceptor
    self.subject = appliesTo
  }

  /// Create an operation, specifying which ``ServerInterceptor`` to apply and to which ``Subject``.
  /// - Parameters:
  ///   - interceptor: The ``ServerInterceptor`` to register with the server.
  ///   - subject: The ``Subject`` to which the `interceptor` applies.
  /// - Returns: A ``ServerInterceptorPipelineOperation``.
  public static func apply(_ interceptor: any ServerInterceptor, to subject: Subject) -> Self {
    Self(interceptor: interceptor, appliesTo: subject)
  }

  /// Returns whether this ``ServerInterceptorPipelineOperation`` applies to the given `descriptor`.
  /// - Parameter descriptor: A ``MethodDescriptor`` for which to test whether this interceptor applies.
  /// - Returns: `true` if this interceptor applies to the given `descriptor`, or `false` otherwise.
  @inlinable
  internal func applies(to descriptor: MethodDescriptor) -> Bool {
    self.subject.applies(to: descriptor)
  }
}
