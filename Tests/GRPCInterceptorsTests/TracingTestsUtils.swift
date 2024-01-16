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

import Tracing
import XCTest

class TracingTestCase: XCTestCase {
  override class func setUp() {
    InstrumentationSystem.bootstrap(TestTracer())
  }
}

public struct TestTracer: Tracer {
  public typealias Span = TestSpan
  
  public func extract<Carrier, Extract>(
    _ carrier: Carrier,
    into context: inout ServiceContextModule.ServiceContext,
    using extractor: Extract
  ) where Carrier == Extract.Carrier, Extract: Instrumentation.Extractor {
    let traceID = extractor.extract(key: TraceID.keyName, from: carrier)
    context[TraceID.self] = traceID
  }

  public func inject<Carrier, Inject>(
    _ context: ServiceContextModule.ServiceContext,
    into carrier: inout Carrier,
    using injector: Inject
  ) where Carrier == Inject.Carrier, Inject: Instrumentation.Injector {
    if let traceID = context.traceID {
      injector.inject(traceID, forKey: TraceID.keyName, into: &carrier)
    }
  }
  
  public func forceFlush() {
    // no-op
  }
  
  public func startSpan<Instant>(
    _ operationName: String,
    context: @autoclosure () -> ServiceContext,
    ofKind kind: SpanKind,
    at instant: @autoclosure () -> Instant,
    function: String,
    file fileID: String,
    line: UInt
  ) -> TestSpan where Instant: TracerInstant {
    TestSpan(context: context(), operationName: operationName)
  }
}

public class TestSpan: Span {
  public var context: ServiceContextModule.ServiceContext
  public var operationName: String
  public var attributes: Tracing.SpanAttributes
  public var isRecording: Bool
  public private(set) var status: Tracing.SpanStatus?
  public private(set) var events: [Tracing.SpanEvent] = []
  
  public init(
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
  
  public func setStatus(_ status: Tracing.SpanStatus) {
      self.status = status
  }
  
  public func addEvent(_ event: Tracing.SpanEvent) {
      self.events.append(event)
  }
  
  public func recordError<Instant>(
      _ error: any Error,
      attributes: Tracing.SpanAttributes,
      at instant: @autoclosure () -> Instant
  ) where Instant: Tracing.TracerInstant {
      self.setStatus(.init(
          code: .error,
          message: "Error: \(error), attributes: \(attributes), at instant: \(instant())"
      ))
  }
  
  public func addLink(_ link: Tracing.SpanLink) {
    self.context.spanLinks?.append(link)
  }
  
  public func end<Instant>(at instant: @autoclosure () -> Instant) where Instant: Tracing.TracerInstant {
    self.setStatus(.init(code: .ok, message: "Ended at instant: \(instant())"))
  }
}

internal enum TraceID: ServiceContextModule.ServiceContextKey {
  typealias Value = String

  static let keyName = "trace-id"
}

internal enum ServiceContextSpanLinksKey: ServiceContextModule.ServiceContextKey {
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
