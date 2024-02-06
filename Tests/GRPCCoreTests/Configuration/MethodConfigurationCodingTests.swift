/*
 * Copyright 2024, gRPC Authors All rights reserved.
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
import SwiftProtobuf
import XCTest

@testable import GRPCCore

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
internal final class MethodConfigurationCodingTests: XCTestCase {
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  private func testDecodeThrowsRuntimeError<D: Decodable>(json: String, as: D.Type) throws {
    XCTAssertThrowsError(
      ofType: RuntimeError.self,
      try self.decoder.decode(D.self, from: Data(json.utf8))
    ) { error in
      XCTAssertEqual(error.code, .invalidArgument)
    }
  }

  func testDecodeMethodConfigName() throws {
    let inputs: [(String, MethodConfiguration.Name)] = [
      (#"{"service": "foo.bar", "method": "baz"}"#, .init(service: "foo.bar", method: "baz")),
      (#"{"service": "foo.bar"}"#, .init(service: "foo.bar", method: "")),
      (#"{}"#, .init(service: "", method: "")),
    ]

    for (json, expected) in inputs {
      let decoded = try self.decoder.decode(MethodConfiguration.Name.self, from: Data(json.utf8))
      XCTAssertEqual(decoded, expected)
    }
  }

  func testEncodeDecodeMethodConfigName() throws {
    let inputs: [MethodConfiguration.Name] = [
      MethodConfiguration.Name(service: "foo.bar", method: "baz"),
      MethodConfiguration.Name(service: "foo.bar", method: ""),
      MethodConfiguration.Name(service: "", method: ""),
    ]

    // We can't do encode-only tests as the output is non-deterministic (the ordering of
    // service/method in the JSON object)
    for name in inputs {
      let encoded = try self.encoder.encode(name)
      let decoded = try self.decoder.decode(MethodConfiguration.Name.self, from: encoded)
      XCTAssertEqual(decoded, name)
    }
  }

  func testDecodeProtobufDuration() throws {
    let inputs: [(String, Duration)] = [
      ("1.0s", .seconds(1)),
      ("1s", .seconds(1)),
      ("1.000000s", .seconds(1)),
      ("0s", .zero),
      ("100.123s", .milliseconds(100_123)),
    ]

    for (input, expected) in inputs {
      let json = "\"\(input)\""
      let protoDuration = try self.decoder.decode(
        GoogleProtobufDuration.self,
        from: Data(json.utf8)
      )
      let components = protoDuration.duration.components

      // Conversion is lossy as we go from floating point seconds to integer seconds and
      // attoseconds. Allow for millisecond precision.
      let divisor: Int64 = 1_000_000_000_000_000

      XCTAssertEqual(components.seconds, expected.components.seconds)
      XCTAssertEqual(components.attoseconds / divisor, expected.components.attoseconds / divisor)
    }
  }

  func testEncodeProtobufDuration() throws {
    let inputs: [(Duration, String)] = [
      (.seconds(1), "\"1.0s\""),
      (.zero, "\"0.0s\""),
      (.milliseconds(100_123), "\"100.123s\""),
    ]

    for (input, expected) in inputs {
      let duration = GoogleProtobufDuration(duration: input)
      let encoded = try self.encoder.encode(duration)
      let json = String(decoding: encoded, as: UTF8.self)
      XCTAssertEqual(json, expected)
    }
  }

  func testDecodeInvalidProtobufDuration() throws {
    for timestamp in ["1", "1ss", "1S", "1.0S"] {
      let json = "\"\(timestamp)\""
      try self.testDecodeThrowsRuntimeError(json: json, as: GoogleProtobufDuration.self)
    }
  }

  func testDecodeRPCCodeFromCaseName() throws {
    let inputs: [(String, Status.Code)] = [
      ("OK", .ok),
      ("CANCELLED", .cancelled),
      ("UNKNOWN", .unknown),
      ("INVALID_ARGUMENT", .invalidArgument),
      ("DEADLINE_EXCEEDED", .deadlineExceeded),
      ("NOT_FOUND", .notFound),
      ("ALREADY_EXISTS", .alreadyExists),
      ("PERMISSION_DENIED", .permissionDenied),
      ("RESOURCE_EXHAUSTED", .resourceExhausted),
      ("FAILED_PRECONDITION", .failedPrecondition),
      ("ABORTED", .aborted),
      ("OUT_OF_RANGE", .outOfRange),
      ("UNIMPLEMENTED", .unimplemented),
      ("INTERNAL", .internalError),
      ("UNAVAILABLE", .unavailable),
      ("DATA_LOSS", .dataLoss),
      ("UNAUTHENTICATED", .unauthenticated),
    ]

    for (name, expected) in inputs {
      let json = "\"\(name)\""
      let code = try self.decoder.decode(GoogleRPCCode.self, from: Data(json.utf8))
      XCTAssertEqual(code.code, expected)
    }
  }

  func testDecodeRPCCodeFromRawValue() throws {
    let inputs: [(Int, Status.Code)] = [
      (0, .ok),
      (1, .cancelled),
      (2, .unknown),
      (3, .invalidArgument),
      (4, .deadlineExceeded),
      (5, .notFound),
      (6, .alreadyExists),
      (7, .permissionDenied),
      (8, .resourceExhausted),
      (9, .failedPrecondition),
      (10, .aborted),
      (11, .outOfRange),
      (12, .unimplemented),
      (13, .internalError),
      (14, .unavailable),
      (15, .dataLoss),
      (16, .unauthenticated),
    ]

    for (rawValue, expected) in inputs {
      let json = "\(rawValue)"
      let code = try self.decoder.decode(GoogleRPCCode.self, from: Data(json.utf8))
      XCTAssertEqual(code.code, expected)
    }
  }

  func testEncodeDecodeRPCCode() throws {
    let codes: [Status.Code] = [
      .ok,
      .cancelled,
      .unknown,
      .invalidArgument,
      .deadlineExceeded,
      .notFound,
      .alreadyExists,
      .permissionDenied,
      .resourceExhausted,
      .failedPrecondition,
      .aborted,
      .outOfRange,
      .unimplemented,
      .internalError,
      .unavailable,
      .dataLoss,
      .unauthenticated,
    ]

    for code in codes {
      let encoded = try self.encoder.encode(GoogleRPCCode(code: code))
      let decoded = try self.decoder.decode(GoogleRPCCode.self, from: encoded)
      XCTAssertEqual(decoded.code, code)
    }
  }

  func testDecodeRetryPolicy() throws {
    let json = """
      {
        "maxAttempts": 3,
        "initialBackoff": "1s",
        "maxBackoff": "3s",
        "backoffMultiplier": 1.6,
        "retryableStatusCodes": ["ABORTED", "UNAVAILABLE"]
      }
      """

    let expected = RetryPolicy(
      maximumAttempts: 3,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(3),
      backoffMultiplier: 1.6,
      retryableStatusCodes: [.aborted, .unavailable]
    )

    let decoded = try self.decoder.decode(RetryPolicy.self, from: Data(json.utf8))
    XCTAssertEqual(decoded, expected)
  }

  func testEncodeDecodeRetryPolicy() throws {
    let policy = RetryPolicy(
      maximumAttempts: 3,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(3),
      backoffMultiplier: 1.6,
      retryableStatusCodes: [.aborted]
    )

    let encoded = try self.encoder.encode(policy)
    let decoded = try self.decoder.decode(RetryPolicy.self, from: encoded)
    XCTAssertEqual(decoded, policy)
  }

  func testDecodeRetryPolicyWithInvalidRetryMaxAttempts() throws {
    let cases = ["-1", "0", "1"]
    for maxAttempts in cases {
      let json = """
        {
          "maxAttempts": \(maxAttempts),
          "initialBackoff": "1s",
          "maxBackoff": "3s",
          "backoffMultiplier": 1.6,
          "retryableStatusCodes": ["ABORTED"]
        }
        """

      try self.testDecodeThrowsRuntimeError(json: json, as: RetryPolicy.self)
    }
  }

  func testDecodeRetryPolicyWithInvalidInitialBackoff() throws {
    let cases = ["0s", "-1s"]
    for backoff in cases {
      let json = """
        {
          "maxAttempts": 3,
          "initialBackoff": "\(backoff)",
          "maxBackoff": "3s",
          "backoffMultiplier": 1.6,
          "retryableStatusCodes": ["ABORTED"]
        }
        """
      try self.testDecodeThrowsRuntimeError(json: json, as: RetryPolicy.self)
    }
  }

  func testDecodeRetryPolicyWithInvalidMaxBackoff() throws {
    let cases = ["0s", "-1s"]
    for backoff in cases {
      let json = """
        {
          "maxAttempts": 3,
          "initialBackoff": "1s",
          "maxBackoff": "\(backoff)",
          "backoffMultiplier": 1.6,
          "retryableStatusCodes": ["ABORTED"]
        }
        """
      try self.testDecodeThrowsRuntimeError(json: json, as: RetryPolicy.self)
    }
  }

  func testDecodeRetryPolicyWithInvalidBackoffMultiplier() throws {
    let cases = ["0", "-1.5"]
    for multiplier in cases {
      let json = """
        {
          "maxAttempts": 3,
          "initialBackoff": "1s",
          "maxBackoff": "3s",
          "backoffMultiplier": \(multiplier),
          "retryableStatusCodes": ["ABORTED"]
        }
        """
      try self.testDecodeThrowsRuntimeError(json: json, as: RetryPolicy.self)
    }
  }

  func testDecodeRetryPolicyWithEmptyRetryableStatusCodes() throws {
    let json = """
      {
        "maxAttempts": 3,
        "initialBackoff": "1s",
        "maxBackoff": "3s",
        "backoffMultiplier": 1,
        "retryableStatusCodes": []
      }
      """
    try self.testDecodeThrowsRuntimeError(json: json, as: RetryPolicy.self)
  }

  func testDecodeHedgingPolicy() throws {
    let json = """
      {
        "maxAttempts": 3,
        "hedgingDelay": "1s",
        "nonFatalStatusCodes": ["ABORTED"]
      }
      """

    let expected = HedgingPolicy(
      maximumAttempts: 3,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: [.aborted]
    )

    let decoded = try self.decoder.decode(HedgingPolicy.self, from: Data(json.utf8))
    XCTAssertEqual(decoded, expected)
  }

  func testEncodeDecodeHedgingPolicy() throws {
    let policy = HedgingPolicy(
      maximumAttempts: 3,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: [.aborted]
    )

    let encoded = try self.encoder.encode(policy)
    let decoded = try self.decoder.decode(HedgingPolicy.self, from: encoded)
    XCTAssertEqual(decoded, policy)
  }

  func testMethodConfigDecodeFromJSON() throws {
    let config = Grpc_ServiceConfig_MethodConfig.with {
      $0.name = [
        .with {
          $0.service = "echo.Echo"
          $0.method = "Get"
        }
      ]

      $0.timeout = .with {
        $0.seconds = 1
        $0.nanos = 0
      }

      $0.maxRequestMessageBytes = 1024
      $0.maxResponseMessageBytes = 2048
    }

    // Test the 'regular' config.
    do {
      let jsonConfig = try config.jsonUTF8Data()
      let decoded = try self.decoder.decode(MethodConfiguration.self, from: jsonConfig)
      XCTAssertEqual(decoded.names, [MethodConfiguration.Name(service: "echo.Echo", method: "Get")])
      XCTAssertEqual(decoded.timeout, Duration(secondsComponent: 1, attosecondsComponent: 0))
      XCTAssertEqual(decoded.maxRequestMessageBytes, 1024)
      XCTAssertEqual(decoded.maxResponseMessageBytes, 2048)
      XCTAssertNil(decoded.executionPolicy)
    }

    // Test the hedging policy.
    do {
      var config = config
      config.hedgingPolicy = .with {
        $0.maxAttempts = 3
        $0.hedgingDelay = .with { $0.seconds = 42 }
        $0.nonFatalStatusCodes = [
          .aborted,
          .unimplemented,
        ]
      }

      let jsonConfig = try config.jsonUTF8Data()
      let decoded = try self.decoder.decode(MethodConfiguration.self, from: jsonConfig)

      switch decoded.executionPolicy {
      case let .some(.hedge(policy)):
        XCTAssertEqual(policy.maximumAttempts, 3)
        XCTAssertEqual(policy.hedgingDelay, .seconds(42))
        XCTAssertEqual(policy.nonFatalStatusCodes, [.aborted, .unimplemented])
      default:
        XCTFail("Expected hedging policy")
      }
    }

    // Test the retry policy.
    do {
      var config = config
      config.retryPolicy = .with {
        $0.maxAttempts = 3
        $0.initialBackoff = .with { $0.seconds = 1 }
        $0.maxBackoff = .with { $0.seconds = 3 }
        $0.backoffMultiplier = 1.6
        $0.retryableStatusCodes = [
          .aborted,
          .unimplemented,
        ]
      }

      let jsonConfig = try config.jsonUTF8Data()
      let decoded = try self.decoder.decode(MethodConfiguration.self, from: jsonConfig)

      switch decoded.executionPolicy {
      case let .some(.retry(policy)):
        XCTAssertEqual(policy.maximumAttempts, 3)
        XCTAssertEqual(policy.initialBackoff, .seconds(1))
        XCTAssertEqual(policy.maximumBackoff, .seconds(3))
        XCTAssertEqual(policy.backoffMultiplier, 1.6)
        XCTAssertEqual(policy.retryableStatusCodes, [.aborted, .unimplemented])
      default:
        XCTFail("Expected hedging policy")
      }
    }
  }
}
