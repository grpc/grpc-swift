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

/// A client interceptor that injects tracing information into the request.
///
/// The tracing information is taken from the current `ServiceContext`, and injected into the request's
/// metadata. It will then be picked up by the server-side ``ServerTracingInterceptor``.
///
/// For more information, refer to the documentation for `swift-distributed-tracing`.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct ClientTracingInterceptor: ClientInterceptor {
  private let injector: ClientRequestInjector
  private let emitEventOnEachWrite: Bool

  /// Create a new instance of a ``ClientTracingInterceptor``.
  ///
  /// - Parameter emitEventOnEachWrite: If `true`, each request part sent and response part
  /// received will be recorded as a separate event in a tracing span. Otherwise, only the request/response
  /// start and end will be recorded as events.
  public init(emitEventOnEachWrite: Bool = false) {
    self.injector = ClientRequestInjector()
    self.emitEventOnEachWrite = emitEventOnEachWrite
  }

  /// This interceptor will inject as the request's metadata whatever `ServiceContext` key-value pairs
  /// have been made available by the tracing implementation bootstrapped in your application.
  ///
  /// Which key-value pairs are injected will depend on the specific tracing implementation
  /// that has been configured when bootstrapping `swift-distributed-tracing` in your application.
  public func intercept<Input, Output>(
    request: ClientRequest.Stream<Input>,
    context: ClientInterceptorContext,
    next: @Sendable (ClientRequest.Stream<Input>, ClientInterceptorContext) async throws ->
      ClientResponse.Stream<Output>
  ) async throws -> ClientResponse.Stream<Output> where Input: Sendable, Output: Sendable {
    var request = request
    let tracer = InstrumentationSystem.tracer
    let serviceContext = ServiceContext.current ?? .topLevel

    tracer.inject(
      serviceContext,
      into: &request.metadata,
      using: self.injector
    )

    return try await tracer.withSpan(
      context.descriptor.fullyQualifiedMethod,
      context: serviceContext,
      ofKind: .client
    ) { span in
      span.addEvent("Request started")

      if self.emitEventOnEachWrite {
        let wrappedProducer = request.producer
        request.producer = { writer in
          let eventEmittingWriter = HookedWriter(
            wrapping: writer,
            beforeEachWrite: {
              span.addEvent("Sending request part")
            },
            afterEachWrite: {
              span.addEvent("Sent request part")
            }
          )

          do {
            try await wrappedProducer(RPCWriter(wrapping: eventEmittingWriter))
          } catch {
            span.addEvent("Error encountered")
            throw error
          }

          span.addEvent("Request end")
        }
      }

      var response: ClientResponse.Stream<Output>
      do {
        response = try await next(request, context)
      } catch {
        span.addEvent("Error encountered")
        throw error
      }

      switch response.accepted {
      case .success(var success):
        if self.emitEventOnEachWrite {
          let onEachPartRecordingSequence = success.bodyParts.map { element in
            span.addEvent("Received response part")
            return element
          }
          let onFinishRecordingSequence = OnFinishAsyncSequence(
            wrapping: onEachPartRecordingSequence
          ) {
            span.addEvent("Received response end")
          }
          success.bodyParts = RPCAsyncSequence(wrapping: onFinishRecordingSequence)
          response.accepted = .success(success)
        } else {
          let onFinishRecordingSequence = OnFinishAsyncSequence(wrapping: success.bodyParts) {
            span.addEvent("Received response end")
          }
          success.bodyParts = RPCAsyncSequence(wrapping: onFinishRecordingSequence)
          response.accepted = .success(success)
        }
      case .failure:
        span.addEvent("Received error response")
      }

      return response
    }
  }
}

/// An injector responsible for injecting the required instrumentation keys from the `ServiceContext` into
/// the request metadata.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct ClientRequestInjector: Instrumentation.Injector {
  typealias Carrier = Metadata

  func inject(_ value: String, forKey key: String, into carrier: inout Carrier) {
    carrier.addString(value, forKey: key)
  }
}
