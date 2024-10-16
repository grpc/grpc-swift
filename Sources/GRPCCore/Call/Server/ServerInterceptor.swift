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
/// Interceptors are registered with the server via ``ServerInterceptorTarget``s.
/// You may register them for all services registered with a server, for RPCs directed to specific services, or
/// for RPCs directed to specific methods. If you need to modify the behavior of an interceptor on a
/// per-RPC basis in more detail, then you can use the ``ServerContext/descriptor`` to determine
/// which RPC is being called and conditionalise behavior accordingly.
///
/// ## RPC filtering
///
/// A common use of server-side interceptors is to filter requests from clients. Interceptors can
/// reject requests which are invalid without service code being called. The following example
/// demonstrates this.
///
/// ```swift
/// struct AuthServerInterceptor: ServerInterceptor {
///   let isAuthorized: @Sendable (String, MethodDescriptor) async throws -> Void
///
///   func intercept<Input: Sendable, Output: Sendable>(
///     request: StreamingServerRequest<Input>,
///     context: ServerContext,
///     next: @Sendable (
///       _ request: StreamingServerRequest<Input>,
///       _ context: ServerContext
///     ) async throws -> StreamingServerResponse<Output>
///   ) async throws -> StreamingServerResponse<Output> {
///     // Extract the auth token.
///     guard let token = request.metadata[stringValues: "authorization"].first(where: { _ in true }) else {
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
/// For client-side interceptors see ``ClientInterceptor``.
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
    request: StreamingServerRequest<Input>,
    context: ServerContext,
    next: @Sendable (
      _ request: StreamingServerRequest<Input>,
      _ context: ServerContext
    ) async throws -> StreamingServerResponse<Output>
  ) async throws -> StreamingServerResponse<Output>
}
