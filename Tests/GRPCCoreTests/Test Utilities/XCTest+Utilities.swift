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
import GRPCCore
import XCTest

func XCTAssertDescription(
  _ subject: some CustomStringConvertible,
  _ expected: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(String(describing: subject), expected, file: file, line: line)
}

func XCTAssertThrowsErrorAsync<T>(
  _ expression: () async throws -> T,
  errorHandler: (Error) -> Void
) async {
  do {
    _ = try await expression()
    XCTFail("Expression didn't throw")
  } catch {
    errorHandler(error)
  }
}

func XCTAssertThrowsError<T, E: Error>(
  ofType: E.Type,
  _ expression: @autoclosure () throws -> T,
  _ errorHandler: (E) -> Void
) {
  XCTAssertThrowsError(try expression()) { error in
    guard let error = error as? E else {
      return XCTFail("Error had unexpected type '\(type(of: error))'")
    }
    errorHandler(error)
  }
}

func XCTAssertThrowsErrorAsync<T, E: Error>(
  ofType: E.Type = E.self,
  _ expression: () async throws -> T,
  errorHandler: (E) -> Void
) async {
  do {
    _ = try await expression()
    XCTFail("Expression didn't throw")
  } catch let error as E {
    errorHandler(error)
  } catch {
    XCTFail("Error had unexpected type '\(type(of: error))'")
  }
}

func XCTAssertThrowsRPCError<T>(
  _ expression: @autoclosure () throws -> T,
  _ errorHandler: (RPCError) -> Void
) {
  XCTAssertThrowsError(try expression()) { error in
    guard let error = error as? RPCError else {
      return XCTFail("Error had unexpected type '\(type(of: error))'")
    }

    errorHandler(error)
  }
}

func XCTAssertThrowsRPCErrorAsync<T>(
  _ expression: () async throws -> T,
  errorHandler: (RPCError) -> Void
) async {
  do {
    _ = try await expression()
    XCTFail("Expression didn't throw")
  } catch let error as RPCError {
    errorHandler(error)
  } catch {
    XCTFail("Error had unexpected type '\(type(of: error))'")
  }
}

func XCTAssertRejected<T>(
  _ response: ClientResponse.Stream<T>,
  errorHandler: (RPCError) -> Void
) {
  switch response.accepted {
  case .success:
    XCTFail("Expected RPC to be rejected")
  case .failure(let error):
    errorHandler(error)
  }
}

func XCTAssertRejected<T>(
  _ response: ClientResponse.Single<T>,
  errorHandler: (RPCError) -> Void
) {
  switch response.accepted {
  case .success:
    XCTFail("Expected RPC to be rejected")
  case .failure(let error):
    errorHandler(error)
  }
}

func XCTAssertMetadata(
  _ part: RPCResponsePart?,
  metadataHandler: (Metadata) -> Void = { _ in }
) {
  switch part {
  case .some(.metadata(let metadata)):
    metadataHandler(metadata)
  default:
    XCTFail("Expected '.metadata' but found '\(String(describing: part))'")
  }
}

func XCTAssertMetadata(
  _ part: RPCRequestPart?,
  metadataHandler: (Metadata) async throws -> Void = { _ in }
) async throws {
  switch part {
  case .some(.metadata(let metadata)):
    try await metadataHandler(metadata)
  default:
    XCTFail("Expected '.metadata' but found '\(String(describing: part))'")
  }
}

func XCTAssertMessage(
  _ part: RPCResponsePart?,
  messageHandler: ([UInt8]) -> Void = { _ in }
) {
  switch part {
  case .some(.message(let message)):
    messageHandler(message)
  default:
    XCTFail("Expected '.message' but found '\(String(describing: part))'")
  }
}

func XCTAssertMessage(
  _ part: RPCRequestPart?,
  messageHandler: ([UInt8]) async throws -> Void = { _ in }
) async throws {
  switch part {
  case .some(.message(let message)):
    try await messageHandler(message)
  default:
    XCTFail("Expected '.message' but found '\(String(describing: part))'")
  }
}

func XCTAssertStatus(
  _ part: RPCResponsePart?,
  statusHandler: (Status, Metadata) -> Void = { _, _ in }
) {
  switch part {
  case .some(.status(let status, let metadata)):
    statusHandler(status, metadata)
  default:
    XCTFail("Expected '.status' but found '\(String(describing: part))'")
  }
}
