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
  private let emitEventOnEachWrite: Bool

  /// Create a new instance of a ``ServerTracingInterceptor``.
  ///
  /// - Parameter emitEventOnEachWrite: If `true`, each response part sent and request part
  /// received will be recorded as a separate event in a tracing span. Otherwise, only the request/response
  /// start and end will be recorded as events.
  public init(emitEventOnEachWrite: Bool = false) {
    self.extractor = ServerRequestExtractor()
    self.emitEventOnEachWrite = emitEventOnEachWrite
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
      using: self.extractor
    )

    return try await ServiceContext.withValue(serviceContext) {
      try await tracer.withSpan(
        context.descriptor.fullyQualifiedMethod,
        context: serviceContext,
        ofKind: .server
      ) { span in
        span.addEvent("Received request start")

        var request = request

        if self.emitEventOnEachWrite {
          request.messages = RPCAsyncSequence(
            wrapping: request.messages.map { element in
              span.addEvent("Received request part")
              return element
            }
          )
        }

        var response = try await next(request, context)

        span.addEvent("Received request end")

        switch response.accepted {
        case .success(var success):
          let wrappedProducer = success.producer

          if self.emitEventOnEachWrite {
            success.producer = { writer in
              let eventEmittingWriter = HookedWriter(
                wrapping: writer,
                beforeEachWrite: {
                  span.addEvent("Sending response part")
                },
                afterEachWrite: {
                  span.addEvent("Sent response part")
                }
              )

              let wrappedResult: Metadata
              do {
                wrappedResult = try await wrappedProducer(
                  RPCWriter(wrapping: eventEmittingWriter)
                )
              } catch {
                span.addEvent("Error encountered")
                throw error
              }

              span.addEvent("Sent response end")
              return wrappedResult
            }
          } else {
            success.producer = { writer in
              let wrappedResult: Metadata
              do {
                wrappedResult = try await wrappedProducer(writer)
              } catch {
                span.addEvent("Error encountered")
                throw error
              }

              span.addEvent("Sent response end")
              return wrappedResult
            }
          }

          response = .init(accepted: .success(success))
        case .failure:
          span.addEvent("Sent error response")
        }

        return response
      }
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
