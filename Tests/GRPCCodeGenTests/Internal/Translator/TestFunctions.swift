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
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftOpenAPIGenerator open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftOpenAPIGenerator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftOpenAPIGenerator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if os(macOS) || os(Linux)  // swift-format doesn't like canImport(Foundation.Process)

import XCTest

import GRPCCodeGen

private func diff(expected: String, actual: String) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = [
    "bash", "-c",
    "diff -U5 --label=expected <(echo '\(expected)') --label=actual <(echo '\(actual)')",
  ]
  let pipe = Pipe()
  process.standardOutput = pipe
  try process.run()
  process.waitUntilExit()
  let pipeData = try XCTUnwrap(
    pipe.fileHandleForReading.readToEnd(),
    """
    No output from command:
    \(process.executableURL!.path) \(process.arguments!.joined(separator: " "))
    """
  )
  return String(decoding: pipeData, as: UTF8.self)
}

internal func XCTAssertEqualWithDiff(
  _ actual: String,
  _ expected: String,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  if actual == expected { return }
  XCTFail(
    """
    XCTAssertEqualWithDiff failed (click for diff)
    \(try diff(expected: expected, actual: actual))
    """,
    file: file,
    line: line
  )
}

internal func makeCodeGenerationRequest(
  services: [CodeGenerationRequest.ServiceDescriptor]
) -> CodeGenerationRequest {
  return CodeGenerationRequest(
    fileName: "test.grpc",
    leadingTrivia: "/// Some really exciting license header 2023.",
    dependencies: [],
    services: services,
    lookupSerializer: {
      "ProtobufSerializer<\($0)>()"
    },
    lookupDeserializer: {
      "ProtobufDeserializer<\($0)>()"
    }
  )
}

internal func makeCodeGenerationRequest(
  dependencies: [CodeGenerationRequest.Dependency]
) -> CodeGenerationRequest {
  return CodeGenerationRequest(
    fileName: "test.grpc",
    leadingTrivia: "/// Some really exciting license header 2023.",
    dependencies: dependencies,
    services: [],
    lookupSerializer: {
      "ProtobufSerializer<\($0)>()"
    },
    lookupDeserializer: {
      "ProtobufDeserializer<\($0)>()"
    }
  )
}

internal func XCTAssertThrowsError<T, E: Error>(
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

#endif  // os(macOS) || os(Linux)
