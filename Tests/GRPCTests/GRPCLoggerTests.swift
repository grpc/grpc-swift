/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
@testable import GRPC
import Logging
import XCTest

final class GRPCLoggerTests: GRPCTestCase {
  func testLogSourceIsGRPC() {
    let recorder = CapturingLogHandlerFactory(printWhenCaptured: false)
    let logger = Logger(label: "io.grpc.testing", factory: recorder.make(_:))

    var gRPCLogger = GRPCLogger(wrapping: logger)
    gRPCLogger[metadataKey: "foo"] = "bar"

    gRPCLogger.debug("foo")
    gRPCLogger.trace("bar")

    let logs = recorder.clearCapturedLogs()
    XCTAssertEqual(logs.count, 2)
    for log in logs {
      XCTAssertEqual(log.source, "GRPC")
      XCTAssertEqual(gRPCLogger[metadataKey: "foo"], "bar")
    }
  }
}
