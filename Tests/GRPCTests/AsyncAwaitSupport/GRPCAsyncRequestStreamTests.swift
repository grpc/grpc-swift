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
final class GRPCAsyncRequestStreamTests: XCTestCase {
  func testRecorder() async throws {
    let testingStream = GRPCAsyncRequestStream<Int>.makeTestingRequestStream()

    testingStream.source.yield(1)
    testingStream.source.finish(throwing: nil)

    let results = try await testingStream.stream.collect()

    XCTAssertEqual(results, [1])
  }
}
