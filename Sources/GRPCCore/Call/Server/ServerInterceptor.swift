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

/// A type that intercepts requests and response for server.
///
/// Interceptors allow you to inspect and modify requests and responses. Requests are intercepted
/// after they have been received by the transport and responses are intercepted after they have
/// been returned from a service. They are typically used for cross-cutting concerns like filtering
/// requests, validating messages, logging additional data, and tracing.
///
/// Interceptors are registered with the server apply to all RPCs. If you need to modify the
/// behavior of an interceptor on a per-RPC basis then you can use the
/// ``ServerInterceptorContext/descriptor`` to determine which RPC is being called and
/// conditionalise behavior accordingly.
///
/// - TODO: Update example and documentation to show how to register an interceptor.
///
/// ## RPC filtering
///
/// A common use of server-side interceptors is to filter requests from clients. Interceptors can
/// reject requests which are invalid without service code being called. The following example
/// demonstrates this.
///
/// ```swift
/// struct AuthServerInterceptor: Sendable {
///   let isAuthorized: @Sendable (String, MethodDescriptor) async throws -> Void
///
///   func intercept<Input: Sendable, Output: Sendable>(
///     request: ServerRequest.Stream<Input>,
///     context: ServerInterceptorContext,
///     next: @Sendable (
///       _ request: ServerRequest.Stream<Input>,
///       _ context: ServerInterceptorContext
///     ) async throws -> ServerResponse.Stream<Output>
///   ) async throws -> ServerResponse.Stream<Output> {
///     // Extract the auth token.
///     guard let token = request.metadata["authorization"] else {
///       throw RPCError(code: .unauthenticated, message: "Not authenticated")
///     }
///
///     // Check whether it's valid.
///     try await self.isAuthorized(token, context.descriptor)
///
///     // Forward the request.
///     return try await next(request, context)
///   }
/// }
/// ```
///
/// For server-side interceptors see ``ClientInterceptor``.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol ServerInterceptor: Sendable {
  /// Intercept a request object.
  ///
  /// - Parameters:
  ///   - request: The request object.
  ///   - context: Additional context about the request, including a descriptor
  ///       of the method being called.
  ///   - next: A closure to invoke to hand off the request and context to the next
  ///       interceptor in the chain.
  /// - Returns: A response object.
  func intercept<Input: Sendable, Output: Sendable>(
    request: ServerRequest.Stream<Input>,
    context: ServerInterceptorContext,
    next: @Sendable (
      _ request: ServerRequest.Stream<Input>,
      _ context: ServerInterceptorContext
    ) async throws -> ServerResponse.Stream<Output>
  ) async throws -> ServerResponse.Stream<Output>
}

/// A context passed to client interceptors containing additional information about the RPC.
public struct ServerInterceptorContext: Sendable {
  /// A description of the method being called.
  public var descriptor: MethodDescriptor

  /// Create a new client interceptor context.
  public init(descriptor: MethodDescriptor) {
    self.descriptor = descriptor
  }
}
