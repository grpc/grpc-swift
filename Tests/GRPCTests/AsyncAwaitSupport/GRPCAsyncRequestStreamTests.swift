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
#if compiler(>=5.6)

import GRPC
import XCTest

@available(macOS 12, iOS 13, tvOS 13, watchOS 6, *)
final class GRPCAsyncRequestStreamTests: XCTestCase {
  func testRecorder() async throws {
    var continuation: AsyncThrowingStream<Int, Error>.Continuation!
    let stream = AsyncThrowingStream<Int, Error> { cont in
      continuation = cont
    }
    let sequence = GRPCAsyncRequestStream<Int>.init(stream)

    continuation.yield(1)

    let results = try await sequence.prefix(1).collect()

    XCTAssertEqual(results, [1])
  }
}
#endif
