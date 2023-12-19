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
final class ClientResponseTests: XCTestCase {
  func testAcceptedSingleResponseConvenienceMethods() {
    let response = ClientResponse.Single(
      message: "message",
      metadata: ["foo": "bar"],
      trailingMetadata: ["bar": "baz"]
    )

    XCTAssertEqual(response.metadata, ["foo": "bar"])
    XCTAssertEqual(try response.message, "message")
    XCTAssertEqual(response.trailingMetadata, ["bar": "baz"])
  }

  func testRejectedSingleResponseConvenienceMethods() {
    let error = RPCError(code: .aborted, message: "error message", metadata: ["bar": "baz"])
    let response = ClientResponse.Single(of: String.self, error: error)

    XCTAssertEqual(response.metadata, [:])
    XCTAssertThrowsRPCError(try response.message) {
      XCTAssertEqual($0, error)
    }
    XCTAssertEqual(response.trailingMetadata, ["bar": "baz"])
  }

  func testAcceptedStreamResponseConvenienceMethods() async throws {
    let response = ClientResponse.Stream(
      of: String.self,
      metadata: ["foo": "bar"],
      bodyParts: RPCAsyncSequence(
        wrapping: AsyncStream {
          $0.yield(.message("foo"))
          $0.yield(.message("bar"))
          $0.yield(.message("baz"))
          $0.yield(.trailingMetadata(["baz": "baz"]))
          $0.finish()
        }
      )
    )

    XCTAssertEqual(response.metadata, ["foo": "bar"])
    let messages = try await response.messages.collect()
    XCTAssertEqual(messages, ["foo", "bar", "baz"])
  }

  func testRejectedStreamResponseConvenienceMethods() async throws {
    let error = RPCError(code: .aborted, message: "error message", metadata: ["bar": "baz"])
    let response = ClientResponse.Stream(of: String.self, error: error)

    XCTAssertEqual(response.metadata, [:])
    await XCTAssertThrowsRPCErrorAsync {
      try await response.messages.collect()
    } errorHandler: {
      XCTAssertEqual($0, error)
    }
  }

  func testStreamToSingleConversionForValidStream() async throws {
    let stream = ClientResponse.Stream(
      of: String.self,
      metadata: ["foo": "bar"],
      bodyParts: .elements(.message("foo"), .trailingMetadata(["bar": "baz"]))
    )

    let single = await ClientResponse.Single(stream: stream)
    XCTAssertEqual(single.metadata, ["foo": "bar"])
    XCTAssertEqual(try single.message, "foo")
    XCTAssertEqual(single.trailingMetadata, ["bar": "baz"])
  }

  func testStreamToSingleConversionForFailedStream() async throws {
    let error = RPCError(code: .aborted, message: "aborted", metadata: ["bar": "baz"])
    let stream = ClientResponse.Stream(of: String.self, error: error)

    let single = await ClientResponse.Single(stream: stream)
    XCTAssertEqual(single.metadata, [:])
    XCTAssertThrowsRPCError(try single.message) {
      XCTAssertEqual($0, error)
    }
    XCTAssertEqual(single.trailingMetadata, ["bar": "baz"])
  }

  func testStreamToSingleConversionForInvalidSingleStream() async throws {
    let bodies: [[ClientResponse.Stream<String>.Contents.BodyPart]] = [
      [.message("1"), .message("2")],  // Too many messages.
      [.trailingMetadata([:])],  // Too few messages
    ]

    for body in bodies {
      let stream = ClientResponse.Stream(
        of: String.self,
        metadata: ["foo": "bar"],
        bodyParts: .elements(body)
      )

      let single = await ClientResponse.Single(stream: stream)
      XCTAssertEqual(single.metadata, [:])
      XCTAssertThrowsRPCError(try single.message) { error in
        XCTAssertEqual(error.code, .unimplemented)
      }
      XCTAssertEqual(single.trailingMetadata, [:])
    }
  }

  func testStreamToSingleConversionForInvalidStream() async throws {
    let bodies: [[ClientResponse.Stream<String>.Contents.BodyPart]] = [
      [],  // Empty stream
      [.trailingMetadata([:]), .trailingMetadata([:])],  // Multiple metadatas
      [.trailingMetadata([:]), .message("")],  // Metadata then message
    ]

    for body in bodies {
      let stream = ClientResponse.Stream(
        of: String.self,
        metadata: ["foo": "bar"],
        bodyParts: .elements(body)
      )

      let single = await ClientResponse.Single(stream: stream)
      XCTAssertEqual(single.metadata, [:])
      XCTAssertThrowsRPCError(try single.message) { error in
        XCTAssertEqual(error.code, .internalError)
      }
      XCTAssertEqual(single.trailingMetadata, [:])
    }
  }

  func testStreamToSingleConversionForStreamThrowingRPCError() async throws {
    let error = RPCError(code: .dataLoss, message: "oops")
    let stream = ClientResponse.Stream(
      of: String.self,
      metadata: [:],
      bodyParts: .throwing(error)
    )

    let single = await ClientResponse.Single(stream: stream)
    XCTAssertThrowsRPCError(try single.message) {
      XCTAssertEqual($0, error)
    }
  }

  func testStreamToSingleConversionForStreamThrowingUnknownError() async throws {
    let stream = ClientResponse.Stream(
      of: String.self,
      metadata: [:],
      bodyParts: .throwing(CancellationError())
    )

    let single = await ClientResponse.Single(stream: stream)
    XCTAssertThrowsRPCError(try single.message) { error in
      XCTAssertEqual(error.code, .unknown)
    }
  }
}
