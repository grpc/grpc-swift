/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import NIOHPACK
import Dispatch

@usableFromInline
struct HPACKHeadersExtractor: Tracing.Extractor {

  @usableFromInline
  init() {}

  @usableFromInline
  func extract(key: String, from headers: HPACKHeaders) -> String? {
    headers.first(name: key)
  }
}

@usableFromInline
struct HPACKHeadersInjector: Tracing.Injector {

  @usableFromInline
  init() {}

  @usableFromInline
  func inject(_ value: String, forKey key: String, into headers: inout HPACKHeaders) {
    headers.add(name: key, value: value)
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------

@available(*, deprecated, message: "Arguably the *real* package should not have such keys declared... but we can push on this a bit I guess")
public struct _GRPCSimpleFixedTraceIDTracer: Tracer {
  typealias Carrier = HPACKHeaders
  public let fixedHeaderName: String

  public init(fixedHeaderName: String) {
    self.fixedHeaderName = fixedHeaderName
  }

  public func startSpan(_ operationName: String, baggage: Baggage, ofKind kind: SpanKind, at time: Dispatch.DispatchWallTime) -> Span {
    fatalError("startSpan(_:baggage:ofKind:at:) has not been implemented")
  }

  public func forceFlush() {
  }

  public func extract<Carrier, Extract>(_ headers: Carrier,
                                 into baggage: inout Baggage,
                                 using extractor: Extract)
      where Extract: Extractor, Extract.Carrier == Carrier {
    if let value = extractor.extract(key: self.fixedHeaderName, from: headers) {
      print("Extracted: \(value)")
      baggage.grpcSimpleFixedTraceID = value
    }
  }

  public func inject<Carrier, Inject>(_ baggage: Baggage,
                               into headers: inout Carrier,
                               using injector: Inject)
      where Inject: Injector, Inject.Carrier == Carrier {
    if let value = baggage.grpcSimpleFixedTraceID {
      print("Injected: \(value)")
      injector.inject(value, forKey: self.fixedHeaderName, into: &headers)
    }
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------

@available(*, deprecated, message: "Arguably the *real* package should not have such keys declared... but we can push on this a bit I guess")
enum GRPCSimpleFixedTraceID: BaggageKey {
  typealias Value = String
  static var nameOverride: String? { "grpc-simple-trace-id" }
}

extension Baggage {
  /// Simple `trace-id` without the need of using actual complete Tracer implementation.
  @available(*, deprecated, message: "Arguably the *real* package should not have such keys declared... but we can push on this a bit I guess")
  public internal(set) var grpcSimpleFixedTraceID: String? {
    get {
      self[GRPCSimpleFixedTraceID.self]
    }
    set {
      self[GRPCSimpleFixedTraceID.self] = newValue
    }
  }
}
