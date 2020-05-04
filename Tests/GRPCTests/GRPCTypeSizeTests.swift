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
import Foundation
import GRPC
import EchoModel
import XCTest

/// These test check the size of types which get wrapped in `NIOAny`. If the size of the type is
/// greater than 24 bytes (the size of the value buffer in an existential container) then it will
/// incur an additional heap allocation.
///
/// This commit message explains the problem and one way to mitigate the issue:
/// https://github.com/apple/swift-nio-http2/commit/4097c3a807a83661f0add383edef29b426e666cb
///
/// Session 416 of WWDC 2016 also provides a good explanation of existential containers.
class GRPCTypeSizeTests: GRPCTestCase {
  let existentialContainerBufferSize = 24

  private func checkSize<T>(of: T.Type, line: UInt = #line) {
    XCTAssertLessThanOrEqual(MemoryLayout<T>.size, self.existentialContainerBufferSize, line: line)
  }

  // `GRPCStatus` isn't wrapped in `NIOAny` but is passed around through functions taking a type
  // conforming to `Error`, so size is important here too.
  func testGRPCStatus() {
    self.checkSize(of: GRPCStatus.self)
  }

  func testGRPCClientRequestPart() {
    self.checkSize(of: _GRPCClientRequestPart<Echo_EchoRequest>.self)
  }

  func testGRPCClientResponsePart() {
    self.checkSize(of: _GRPCClientResponsePart<Echo_EchoResponse>.self)
  }
}
