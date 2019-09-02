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
import Foundation
import GRPC
import NIOHTTP1
import XCTest

extension RawGRPCServerResponsePart {
  /// Asserts that this value represents the headers case.
  ///
  /// - Parameter validate: A block to further validate the headers.
  func assertHeaders(validate: ((HTTPHeaders) -> Void)? = nil) {
    guard case .headers(let headers) = self else {
      XCTFail("Expected .headers but got \(self)")
      return
    }
    validate?(headers)
  }

  /// Asserts that this value represents the message case.
  ///
  /// - Parameter validate: A block to further validate the message.
  func assertMessage(validate: ((Data) -> Void)? = nil) {
    guard case .message(let message) = self else {
      XCTFail("Expected .message but got \(self)")
      return
    }
    validate?(message)
  }

  /// Asserts that this value represents the status case.
  ///
  /// - Parameter validate: A block to further validate the status.
  func assertStatus(validate: ((GRPCStatus) -> Void)? = nil) {
    guard case let .statusAndTrailers(status, _) = self else {
      XCTFail("Expected .status but got \(self)")
      return
    }
    validate?(status)
  }
}
