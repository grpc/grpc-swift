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
import GRPC
import Logging
import NIOConcurrencyHelpers
import XCTest

#if compiler(>=5.6)
// Unchecked as all mutable state is accessed and modified behind a lock.
extension ErrorRecordingDelegate: @unchecked Sendable {}
#endif // compiler(>=5.6)

final class ErrorRecordingDelegate: ClientErrorDelegate {
  private let lock: NIOLock
  private var _errors: [Error] = []

  internal var errors: [Error] {
    return self.lock.withLock {
      return self._errors
    }
  }

  var expectation: XCTestExpectation

  init(expectation: XCTestExpectation) {
    self.expectation = expectation
    self.lock = NIOLock()
  }

  func didCatchError(_ error: Error, logger: Logger, file: StaticString, line: Int) {
    self.lock.withLock {
      self._errors.append(error)
    }
    self.expectation.fulfill()
  }
}

class ServerErrorRecordingDelegate: ServerErrorDelegate {
  var errors: [Error] = []
  var expectation: XCTestExpectation

  init(expectation: XCTestExpectation) {
    self.expectation = expectation
  }

  func observeLibraryError(_ error: Error) {
    self.errors.append(error)
    self.expectation.fulfill()
  }
}
