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
@testable import GRPC
import Logging
import NIOCore
import NIOEmbedded
import NIOSSL
import XCTest

class DelegatingErrorHandlerTests: GRPCTestCase {
  final class ErrorRecorder: ClientErrorDelegate {
    var errors: [Error] = []

    init() {}

    func didCatchError(_ error: Error, logger: Logger, file: StaticString, line: Int) {
      self.errors.append(error)
    }
  }

  func testUncleanShutdownIsIgnored() throws {
    let delegate = ErrorRecorder()
    let channel =
      EmbeddedChannel(handler: DelegatingErrorHandler(logger: self.logger, delegate: delegate))
    channel.pipeline.fireErrorCaught(NIOSSLError.uncleanShutdown)
    channel.pipeline.fireErrorCaught(NIOSSLError.writeDuringTLSShutdown)

    XCTAssertEqual(delegate.errors.count, 1)
    XCTAssertEqual(delegate.errors[0] as? NIOSSLError, .writeDuringTLSShutdown)
  }
}

// Unchecked because the error recorder is only ever used in the context of an EmbeddedChannel.
extension DelegatingErrorHandlerTests.ErrorRecorder: @unchecked Sendable {}
#endif // canImport(NIOSSL)
