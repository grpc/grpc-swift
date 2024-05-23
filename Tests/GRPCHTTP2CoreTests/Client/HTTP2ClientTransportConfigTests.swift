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

import GRPCHTTP2Core
import XCTest

final class HTTP2ClientTransportConfigTests: XCTestCase {
  func testCompressionDefaults() {
    let config = HTTP2ClientTransport.Config.Compression.defaults
    XCTAssertEqual(config.algorithm, .none)
    XCTAssertEqual(config.enabledAlgorithms, .none)
  }

  func testIdleDefaults() {
    let config = HTTP2ClientTransport.Config.Idle.defaults
    XCTAssertEqual(config.maxTime, .seconds(30 * 60))
  }

  func testBackoffDefaults() {
    let config = HTTP2ClientTransport.Config.Backoff.defaults
    XCTAssertEqual(config.initial, .seconds(1))
    XCTAssertEqual(config.max, .seconds(120))
    XCTAssertEqual(config.multiplier, 1.6)
    XCTAssertEqual(config.jitter, 0.2)
  }

  func testHTTP2Defaults() {
    let config = HTTP2ClientTransport.Config.HTTP2.defaults
    XCTAssertEqual(config.maxFrameSize, 16384)
    XCTAssertEqual(config.targetWindowSize, 8 * 1024 * 1024)
  }
}
