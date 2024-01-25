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

/// A type that intercepts requests and response for clients.
///
/// Interceptors allow you to inspect and modify requests and responses. Requests are intercepted
/// before they are handed to a transport and responses are intercepted after they have been
/// received from the transport. They are typically used for cross-cutting concerns like injecting
/// metadata, validating messages, logging additional data, and tracing.
///
/// Interceptors are registered with a client and apply to all RPCs. If you need to modify the
/// behavior of an interceptor on a per-RPC basis then you can use the
/// ``ClientInterceptorContext/descriptor`` to determine which RPC is being called and
/// conditionalise behavior accordingly.
///
/// - TODO: Update example and documentation to show how to register an interceptor.
///
/// Some examples of simple interceptors follow.
///
/// ## Metadata injection
///
/// A common use-case for client interceptors is injecting metadata into a request.
///
/// ```swift
/// struct MetadataInjectingClientInterceptor: ClientInterceptor {
///   let key: String
///   let fetchMetadata: @Sendable () async -> String
///
///   func intercept<Input: Sendable, Output: Sendable>(
///     request: ClientRequest.Stream<Input>,
///     context: ClientInterceptorContext,
///     next: @Sendable (
///       _ request: ClientRequest.Stream<Input>,
///       _ context: ClientInterceptorContext
///     ) async throws -> ClientResponse.Stream<Output>
///   ) async throws -> ClientResponse.Stream<Output> {
///     // Fetch the metadata value and attach it.
///     let value = await self.fetchMetadata()
///     var request = request
///     request.metadata[self.key] = value
///
///     // Forward the request to the next interceptor.
///     return try await next(request, context)
///   }
/// }
/// ```
///
/// Interceptors can also be used to print information about RPCs.
///
/// ## Logging interceptor
///
/// ```swift
/// struct LoggingClientInterceptor: ClientInterceptor {
///   func intercept<Input: Sendable, Output: Sendable>(
///     request: ClientRequest.Stream<Input>,
///     context: ClientInterceptorContext,
///     next: @Sendable (
///       _ request: ClientRequest.Stream<Input>,
///       _ context: ClientInterceptorContext
///     ) async throws -> ClientResponse.Stream<Output>
///   ) async throws -> ClientResponse.Stream<Output> {
///     print("Invoking method '\(context.descriptor)'")
///     let response = try await next(request, context)
///
///     switch response.accepted {
///     case .success:
///       print("Server accepted RPC for processing")
///     case .failure(let error):
///       print("Server rejected RPC with error '\(error)'")
///     }
///
///     return response
///   }
/// }
/// ```
///
/// For server-side interceptors see ``ServerInterceptor``.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol ClientInterceptor: Sendable {
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
    request: ClientRequest.Stream<Input>,
    context: ClientInterceptorContext,
    next: @Sendable (
      _ request: ClientRequest.Stream<Input>,
      _ context: ClientInterceptorContext
    ) async throws -> ClientResponse.Stream<Output>
  ) async throws -> ClientResponse.Stream<Output>
}

/// A context passed to client interceptors containing additional information about the RPC.
public struct ClientInterceptorContext: Sendable {
  /// A description of the method being called.
  public var descriptor: MethodDescriptor

  /// Create a new client interceptor context.
  public init(descriptor: MethodDescriptor) {
    self.descriptor = descriptor
  }
}
