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
import XCTest

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
internal func XCTAssertThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  verify: (Error) -> Void = { _ in },
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expression did not throw error", file: file, line: line)
  } catch {
    verify(error)
  }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
internal func XCTAssertNoThrowAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
  } catch {
    XCTFail("Expression throw error '\(error)'", file: file, line: line)
  }
}

private enum TaskResult<Result> {
  case operation(Result)
  case cancellation
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
func withTaskCancelledAfter<Result>(
  nanoseconds: UInt64,
  operation: @escaping @Sendable () async -> Result
) async throws {
  try await withThrowingTaskGroup(of: TaskResult<Result>.self) { group in
    group.addTask {
      return .operation(await operation())
    }

    group.addTask {
      try await Task.sleep(nanoseconds: nanoseconds)
      return .cancellation
    }

    // Only the sleeping task can throw if it's cancelled, in which case we want to throw.
    let firstResult = try await group.next()
    // A task completed, cancel the rest.
    group.cancelAll()

    // Check which task completed.
    switch firstResult {
    case .cancellation:
      () // Fine, what we expect.
    case .operation:
      XCTFail("Operation completed before cancellation")
    case .none:
      XCTFail("No tasks completed")
    }

    // Wait for the other task. The operation cannot, only the sleeping task can.
    try await group.waitForAll()
  }
}
