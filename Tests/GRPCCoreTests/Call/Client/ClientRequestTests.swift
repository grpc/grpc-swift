/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

import XCTest

@testable import GRPCCore

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class ClientRequestTests: XCTestCase {
  func testSingleToStreamConversion() async throws {
    let (messages, continuation) = AsyncStream.makeStream(of: String.self)
    let single = ClientRequest.Single(message: "foo", metadata: ["bar": "baz"])
    let stream = ClientRequest.Stream(single: single)

    XCTAssertEqual(stream.metadata, ["bar": "baz"])
    try await stream.producer(.gathering(into: continuation))
    continuation.finish()
    let collected = try await messages.collect()
    XCTAssertEqual(collected, ["foo"])
  }
}
