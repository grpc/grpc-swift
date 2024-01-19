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
import NIOConcurrencyHelpers
import Tracing

final class TestTracer: Tracer {
  typealias Span = TestSpan

  private var testSpans: NIOLockedValueBox<[String: TestSpan]> = .init([:])

  func getEventsForTestSpan(ofOperationName operationName: String) -> [SpanEvent] {
    self.testSpans.withLockedValue({ $0[operationName] })?.events ?? []
  }

  func extract<Carrier, Extract>(
    _ carrier: Carrier,
    into context: inout ServiceContextModule.ServiceContext,
    using extractor: Extract
  ) where Carrier == Extract.Carrier, Extract: Instrumentation.Extractor {
    let traceID = extractor.extract(key: TraceID.keyName, from: carrier)
    context[TraceID.self] = traceID
  }

  func inject<Carrier, Inject>(
    _ context: ServiceContextModule.ServiceContext,
    into carrier: inout Carrier,
    using injector: Inject
  ) where Carrier == Inject.Carrier, Inject: Instrumentation.Injector {
    if let traceID = context.traceID {
      injector.inject(traceID, forKey: TraceID.keyName, into: &carrier)
    }
  }

  func forceFlush() {
    // no-op
  }

  func startSpan<Instant>(
    _ operationName: String,
    context: @autoclosure () -> ServiceContext,
    ofKind kind: SpanKind,
    at instant: @autoclosure () -> Instant,
    function: String,
    file fileID: String,
    line: UInt
  ) -> TestSpan where Instant: TracerInstant {
    return self.testSpans.withLockedValue { testSpans in
      let span = TestSpan(context: context(), operationName: operationName)
      testSpans[operationName] = span
      return span
    }
  }
}

class TestSpan: Span {
  var context: ServiceContextModule.ServiceContext
  var operationName: String
  var attributes: Tracing.SpanAttributes
  var isRecording: Bool
  private(set) var status: Tracing.SpanStatus?
  private(set) var events: [Tracing.SpanEvent] = []

  init(
    context: ServiceContextModule.ServiceContext,
    operationName: String,
    attributes: Tracing.SpanAttributes = [:],
    isRecording: Bool = true
  ) {
    self.context = context
    self.operationName = operationName
    self.attributes = attributes
    self.isRecording = isRecording
  }

  func setStatus(_ status: Tracing.SpanStatus) {
    self.status = status
  }

  func addEvent(_ event: Tracing.SpanEvent) {
    self.events.append(event)
  }

  func recordError<Instant>(
    _ error: any Error,
    attributes: Tracing.SpanAttributes,
    at instant: @autoclosure () -> Instant
  ) where Instant: Tracing.TracerInstant {
    self.setStatus(
      .init(
        code: .error,
        message: "Error: \(error), attributes: \(attributes), at instant: \(instant())"
      )
    )
  }

  func addLink(_ link: Tracing.SpanLink) {
    self.context.spanLinks?.append(link)
  }

  func end<Instant>(at instant: @autoclosure () -> Instant) where Instant: Tracing.TracerInstant {
    self.setStatus(.init(code: .ok, message: "Ended at instant: \(instant())"))
  }
}

enum TraceID: ServiceContextModule.ServiceContextKey {
  typealias Value = String

  static let keyName = "trace-id"
}

enum ServiceContextSpanLinksKey: ServiceContextModule.ServiceContextKey {
  typealias Value = [SpanLink]

  static let keyName = "span-links"
}

extension ServiceContext {
  var traceID: String? {
    get {
      self[TraceID.self]
    }
    set {
      self[TraceID.self] = newValue
    }
  }

  var spanLinks: [SpanLink]? {
    get {
      self[ServiceContextSpanLinksKey.self]
    }
    set {
      self[ServiceContextSpanLinksKey.self] = newValue
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct TestWriter<WriterElement>: RPCWriterProtocol {
  typealias Element = WriterElement

  private let streamContinuation: AsyncStream<Element>.Continuation

  init(streamContinuation: AsyncStream<Element>.Continuation) {
    self.streamContinuation = streamContinuation
  }

  func write(contentsOf elements: some Sequence<Self.Element>) async throws {
    elements.forEach { element in
      self.streamContinuation.yield(element)
    }
  }
}

#if swift(<5.9)
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension AsyncStream {
  static func makeStream(
    of elementType: Element.Type = Element.self,
    bufferingPolicy limit: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded
  ) -> (stream: AsyncStream<Element>, continuation: AsyncStream<Element>.Continuation) {
    var continuation: AsyncStream<Element>.Continuation!
    let stream = AsyncStream(Element.self, bufferingPolicy: limit) {
      continuation = $0
    }
    return (stream, continuation)
  }
}
#endif
