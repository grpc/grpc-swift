/*
 * Copyright 2020, gRPC Authors All rights reserved.
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

@testable import GRPC

class MessageEncodingHeaderValidatorTests: GRPCTestCase {
  func testSupportedAlgorithm() throws {
    let validator = MessageEncodingHeaderValidator(
      encoding: .enabled(
        .init(
          enabledAlgorithms: [.deflate, .gzip],
          decompressionLimit: .absolute(10)
        )
      )
    )

    let validation = validator.validate(requestEncoding: "gzip")
    switch validation {
    case .supported(.gzip, .absolute(10), acceptEncoding: []):
      ()  // Expected
    default:
      XCTFail("Expected .supported but was \(validation)")
    }
  }

  func testSupportedButNotAdvertisedAlgorithm() throws {
    let validator = MessageEncodingHeaderValidator(
      encoding: .enabled(.init(enabledAlgorithms: [.deflate], decompressionLimit: .absolute(10)))
    )

    let validation = validator.validate(requestEncoding: "gzip")
    switch validation {
    case .supported(.gzip, .absolute(10), acceptEncoding: ["deflate", "gzip"]):
      ()  // Expected
    default:
      XCTFail("Expected .supported but was \(validation)")
    }
  }

  func testSupportedButExplicitlyDisabled() throws {
    let validator = MessageEncodingHeaderValidator(encoding: .disabled)

    let validation = validator.validate(requestEncoding: "gzip")
    switch validation {
    case .unsupported(requestEncoding: "gzip", acceptEncoding: []):
      ()  // Expected
    default:
      XCTFail("Expected .unsupported but was \(validation)")
    }
  }

  func testUnsupportedButEnabled() throws {
    let validator = MessageEncodingHeaderValidator(
      encoding:
        .enabled(.init(enabledAlgorithms: [.gzip], decompressionLimit: .absolute(10)))
    )

    let validation = validator.validate(requestEncoding: "not-supported")
    switch validation {
    case .unsupported(requestEncoding: "not-supported", acceptEncoding: ["gzip"]):
      ()  // Expected
    default:
      XCTFail("Expected .unsupported but was \(validation)")
    }
  }

  func testNoCompressionWhenExplicitlyDisabled() throws {
    let validator = MessageEncodingHeaderValidator(encoding: .disabled)

    let validation = validator.validate(requestEncoding: nil)
    switch validation {
    case .noCompression:
      ()  // Expected
    default:
      XCTFail("Expected .noCompression but was \(validation)")
    }
  }

  func testNoCompressionWhenEnabled() throws {
    let validator = MessageEncodingHeaderValidator(
      encoding:
        .enabled(
          .init(
            enabledAlgorithms: CompressionAlgorithm.all,
            decompressionLimit: .absolute(10)
          )
        )
    )

    let validation = validator.validate(requestEncoding: nil)
    switch validation {
    case .noCompression:
      ()  // Expected
    default:
      XCTFail("Expected .noCompression but was \(validation)")
    }
  }
}
