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
import XCTest

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
