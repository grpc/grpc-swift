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

public struct TestTracer: Instrumentation.Instrument {
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
}

internal enum TraceID: ServiceContextModule.ServiceContextKey {
  typealias Value = String

  static let keyName = "trace-id"
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
}
