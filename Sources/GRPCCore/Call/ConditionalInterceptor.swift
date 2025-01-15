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

/// Describes the conditions under which an interceptor should be applied.
///
/// You can configure interceptors to be applied to:
/// - all RPCs and services;
/// - requests directed only to specific services; or
/// - requests directed only to specific methods (of a specific service).
///
/// - SeeAlso: ``ClientInterceptor`` and ``ServerInterceptor`` for more information on client and
///   server interceptors, respectively.
public struct ConditionalInterceptor<Interceptor: Sendable>: Sendable {
  public struct Subject: Sendable {
    internal enum Wrapped: Sendable {
      case all
      case services(Set<ServiceDescriptor>)
      case methods(Set<MethodDescriptor>)
    }

    private let wrapped: Wrapped

    /// An operation subject specifying an interceptor that applies to all RPCs across all services will be registered with this client.
    public static var all: Self { .init(wrapped: .all) }

    /// An operation subject specifying an interceptor that will be applied only to RPCs directed to the specified services.
    /// - Parameters:
    ///   - services: The list of service names for which this interceptor should intercept RPCs.
    public static func services(_ services: Set<ServiceDescriptor>) -> Self {
      Self(wrapped: .services(services))
    }

    /// An operation subject specifying an interceptor that will be applied only to RPCs directed to the specified service methods.
    /// - Parameters:
    ///   - methods: The list of method descriptors for which this interceptor should intercept RPCs.
    public static func methods(_ methods: Set<MethodDescriptor>) -> Self {
      Self(wrapped: .methods(methods))
    }

    @usableFromInline
    package func applies(to descriptor: MethodDescriptor) -> Bool {
      switch self.wrapped {
      case .all:
        return true

      case .services(let services):
        return services.contains(descriptor.service)

      case .methods(let methods):
        return methods.contains(descriptor)
      }
    }
  }

  /// The interceptor.
  public let interceptor: Interceptor

  @usableFromInline
  internal let subject: Subject

  fileprivate init(interceptor: Interceptor, subject: Subject) {
    self.interceptor = interceptor
    self.subject = subject
  }

  /// Returns whether this ``ClientInterceptorPipelineOperation`` applies to the given `descriptor`.
  /// - Parameter descriptor: A ``MethodDescriptor`` for which to test whether this interceptor applies.
  /// - Returns: `true` if this interceptor applies to the given `descriptor`, or `false` otherwise.
  @inlinable
  internal func applies(to descriptor: MethodDescriptor) -> Bool {
    self.subject.applies(to: descriptor)
  }
}

extension ConditionalInterceptor where Interceptor == any ClientInterceptor {
  /// Create an operation, specifying which ``ClientInterceptor`` to apply and to which ``Subject``.
  /// - Parameters:
  ///   - interceptor: The ``ClientInterceptor`` to register with the client.
  ///   - subject: The ``Subject`` to which the `interceptor` applies.
  public static func apply(
    _ interceptor: any ClientInterceptor,
    to subject: Subject
  ) -> Self {
    Self(interceptor: interceptor, subject: subject)
  }
}

extension ConditionalInterceptor where Interceptor == any ServerInterceptor {
  /// Create an operation, specifying which ``ServerInterceptor`` to apply and to which ``Subject``.
  /// - Parameters:
  ///   - interceptor: The ``ServerInterceptor`` to register with the client.
  ///   - subject: The ``Subject`` to which the `interceptor` applies.
  public static func apply(
    _ interceptor: any ServerInterceptor,
    to subject: Subject
  ) -> Self {
    Self(interceptor: interceptor, subject: subject)
  }
}
