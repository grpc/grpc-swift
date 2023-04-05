/*
 * Copyright 2022, gRPC Authors All rights reserved.
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

import GRPC
import XCTest

@available(macOS 12, iOS 13, tvOS 13, watchOS 6, *)
final class GRPCAsyncResponseStreamWriterTests: XCTestCase {
  func testRecorder() async throws {
    let responseStreamWriter = GRPCAsyncResponseStreamWriter<Int>.makeTestingResponseStreamWriter()

    try await responseStreamWriter.writer.send(1, compression: .disabled)
    responseStreamWriter.stream.finish()

    let results = try await responseStreamWriter.stream.collect()
    XCTAssertEqual(results[0].0, 1)
    XCTAssertEqual(results[0].1, .disabled)
  }
}
