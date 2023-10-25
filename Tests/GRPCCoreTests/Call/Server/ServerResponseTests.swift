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
@_spi(Testing) import GRPCCore
import XCTest

final class ServerResponseTests: XCTestCase {
  func testSingleConvenienceInit() {
    var response = ServerResponse.Single(
      message: "message",
      metadata: ["metadata": "initial"],
      trailingMetadata: ["metadata": "trailing"]
    )

    switch response.accepted {
    case .success(let contents):
      XCTAssertEqual(contents.message, "message")
      XCTAssertEqual(contents.metadata, ["metadata": "initial"])
      XCTAssertEqual(contents.trailingMetadata, ["metadata": "trailing"])
    case .failure:
      XCTFail("Unexpected error")
    }

    let error = RPCError(code: .aborted, message: "Aborted")
    response = ServerResponse.Single(of: String.self, error: error)
    switch response.accepted {
    case .success:
      XCTFail("Unexpected success")
    case .failure(let error):
      XCTAssertEqual(error, error)
    }
  }

  func testStreamConvenienceInit() async throws {
    var response = ServerResponse.Stream(of: String.self, metadata: ["metadata": "initial"]) { _ in
      // Empty body.
      return ["metadata": "trailing"]
    }

    switch response.accepted {
    case .success(let contents):
      XCTAssertEqual(contents.metadata, ["metadata": "initial"])
      let trailingMetadata = try await contents.producer(.failTestOnWrite())
      XCTAssertEqual(trailingMetadata, ["metadata": "trailing"])
    case .failure:
      XCTFail("Unexpected error")
    }

    let error = RPCError(code: .aborted, message: "Aborted")
    response = ServerResponse.Stream(of: String.self, error: error)
    switch response.accepted {
    case .success:
      XCTFail("Unexpected success")
    case .failure(let error):
      XCTAssertEqual(error, error)
    }
  }

  func testSingleToStreamConversionForSuccessfulResponse() async throws {
    let single = ServerResponse.Single(
      message: "foo",
      metadata: ["metadata": "initial"],
      trailingMetadata: ["metadata": "trailing"]
    )

    let stream = ServerResponse.Stream(single: single)
    let (messages, continuation) = AsyncStream.makeStream(of: String.self)
    let trailingMetadata: Metadata

    switch stream.accepted {
    case .success(let contents):
      trailingMetadata = try await contents.producer(.gathering(into: continuation))
      continuation.finish()
    case .failure(let error):
      throw error
    }

    XCTAssertEqual(stream.metadata, ["metadata": "initial"])
    let collected = try await messages.collect()
    XCTAssertEqual(collected, ["foo"])
    XCTAssertEqual(trailingMetadata, ["metadata": "trailing"])
  }

  func testSingleToStreamConversionForFailedResponse() async throws {
    let error = RPCError(code: .aborted, message: "aborted")
    let single = ServerResponse.Single(of: String.self, error: error)
    let stream = ServerResponse.Stream(single: single)

    XCTAssertThrowsRPCError(try stream.accepted.get()) {
      XCTAssertEqual($0, error)
    }
  }
}
