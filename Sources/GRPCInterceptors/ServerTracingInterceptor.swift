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

import GRPCCore
import Tracing

/// A server interceptor that extracts tracing information from the request.
///
/// The extracted tracing information is made available to user code via the current `ServiceContext`.
/// For more information, refer to the documentation for `swift-distributed-tracing`.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct ServerTracingInterceptor: ServerInterceptor {
  private let extractor: ServerRequestExtractor

  /// Create a new instance of a ``ServerTracingInterceptor``.
  public init() {
    self.extractor = ServerRequestExtractor()
  }

  /// This interceptor will extract whatever `ServiceContext` key-value pairs have been inserted into the
  /// request's metadata, and will make them available to user code via the `ServiceContext/current`
  /// context.
  ///
  /// Which key-value pairs are extracted and made available will depend on the specific tracing implementation
  /// that has been configured when bootstrapping `swift-distributed-tracing` in your application.
  public func intercept<Input, Output>(
    request: ServerRequest.Stream<Input>,
    context: ServerInterceptorContext,
    next: @Sendable (ServerRequest.Stream<Input>, ServerInterceptorContext) async throws ->
      ServerResponse.Stream<Output>
  ) async throws -> ServerResponse.Stream<Output> where Input: Sendable, Output: Sendable {
    var serviceContext = ServiceContext.topLevel
    let tracer = InstrumentationSystem.tracer
      
    tracer.extract(
      request.metadata,
      into: &serviceContext,
      using: ServerRequestExtractor()
    )
    
    return try await tracer.withSpan(context.descriptor.fullyQualifiedMethod, context: serviceContext, ofKind: .server) { span in
      span.addEvent("Received request")
      let response = try await next(request, context)
      span.addEvent("Sending response")
      return response
    }
  }
}

/// An extractor responsible for extracting the required instrumentation keys from request metadata.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct ServerRequestExtractor: Instrumentation.Extractor {
  typealias Carrier = Metadata

  func extract(key: String, from carrier: Carrier) -> String? {
    var values = carrier[stringValues: key].makeIterator()
    // There should only be one value for each key. If more, pick just one.
    return values.next()
  }
}
