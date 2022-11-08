/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
#if canImport(NIOSSL)
import Foundation
import GRPCSampleData
import XCTest

extension SampleCertificate {
  func assertNotExpired(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(
      self.isExpired,
      "Certificate expired at \(self.notAfter)",
      // swiftformat:disable:next redundantParens
      file: (file),
      line: line
    )
  }
}
#endif // canImport(NIOSSL)
