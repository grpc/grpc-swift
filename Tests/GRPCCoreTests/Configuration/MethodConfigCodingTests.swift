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
import Testing

@testable import GRPCCore

@Suite("MethodConfig coding tests")
struct MethodConfigCodingTests {
  @Suite("Encoding")
  struct Encoding {
    private func encodeToJSON(_ value: some Encodable) throws -> String {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      let encoded = try encoder.encode(value)
      let json = String(decoding: encoded, as: UTF8.self)
      return json
    }

    @Test(
      "Name",
      arguments: [
        (
          MethodConfig.Name(service: "foo.bar", method: "baz"),
          #"{"method":"baz","service":"foo.bar"}"#
        ),
        (MethodConfig.Name(service: "foo.bar", method: ""), #"{"method":"","service":"foo.bar"}"#),
        (MethodConfig.Name(service: "", method: ""), #"{"method":"","service":""}"#),
      ] as [(MethodConfig.Name, String)]
    )
    func methodConfigName(name: MethodConfig.Name, expected: String) throws {
      let json = try self.encodeToJSON(name)
      #expect(json == expected)
    }

    @Test(
      "GoogleProtobufDuration",
      arguments: [
        (.seconds(1), #""1.0s""#),
        (.zero, #""0.0s""#),
        (.milliseconds(100_123), #""100.123s""#),
      ] as [(Duration, String)]
    )
    func protobufDuration(duration: Duration, expected: String) throws {
      let json = try self.encodeToJSON(GoogleProtobufDuration(duration: duration))
      #expect(json == expected)
    }

    @Test(
      "GoogleRPCCode",
      arguments: [
        (.ok, #""OK""#),
        (.cancelled, #""CANCELLED""#),
        (.unknown, #""UNKNOWN""#),
        (.invalidArgument, #""INVALID_ARGUMENT""#),
        (.deadlineExceeded, #""DEADLINE_EXCEEDED""#),
        (.notFound, #""NOT_FOUND""#),
        (.alreadyExists, #""ALREADY_EXISTS""#),
        (.permissionDenied, #""PERMISSION_DENIED""#),
        (.resourceExhausted, #""RESOURCE_EXHAUSTED""#),
        (.failedPrecondition, #""FAILED_PRECONDITION""#),
        (.aborted, #""ABORTED""#),
        (.outOfRange, #""OUT_OF_RANGE""#),
        (.unimplemented, #""UNIMPLEMENTED""#),
        (.internalError, #""INTERNAL""#),
        (.unavailable, #""UNAVAILABLE""#),
        (.dataLoss, #""DATA_LOSS""#),
        (.unauthenticated, #""UNAUTHENTICATED""#),
      ] as [(Status.Code, String)]
    )
    func rpcCode(code: Status.Code, expected: String) throws {
      let json = try self.encodeToJSON(GoogleRPCCode(code: code))
      #expect(json == expected)
    }

    @Test("RetryPolicy")
    func retryPolicy() throws {
      let policy = RetryPolicy(
        maxAttempts: 3,
        initialBackoff: .seconds(1),
        maxBackoff: .seconds(3),
        backoffMultiplier: 1.6,
        retryableStatusCodes: [.aborted]
      )

      let json = try self.encodeToJSON(policy)
      let expected =
        #"{"backoffMultiplier":1.6,"initialBackoff":"1.0s","maxAttempts":3,"maxBackoff":"3.0s","retryableStatusCodes":["ABORTED"]}"#
      #expect(json == expected)
    }

    @Test("HedgingPolicy")
    func hedgingPolicy() throws {
      let policy = HedgingPolicy(
        maxAttempts: 3,
        hedgingDelay: .seconds(1),
        nonFatalStatusCodes: [.aborted]
      )

      let json = try self.encodeToJSON(policy)
      let expected = #"{"hedgingDelay":"1.0s","maxAttempts":3,"nonFatalStatusCodes":["ABORTED"]}"#
      #expect(json == expected)
    }
  }

  @Suite("Decoding")
  struct Decoding {
    private func decodeFromFile<Decoded: Decodable>(
      _ name: String,
      as: Decoded.Type
    ) throws -> Decoded {
      let input = Bundle.module.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Inputs"
      )

      let url = try #require(input)
      let data = try Data(contentsOf: url)

      let decoder = JSONDecoder()
      return try decoder.decode(Decoded.self, from: data)
    }

    private func decodeFromJSONString<Decoded: Decodable>(
      _ json: String,
      as: Decoded.Type
    ) throws -> Decoded {
      let data = Data(json.utf8)
      let decoder = JSONDecoder()
      return try decoder.decode(Decoded.self, from: data)
    }

    private static let codeNames: [String] = [
      "OK",
      "CANCELLED",
      "UNKNOWN",
      "INVALID_ARGUMENT",
      "DEADLINE_EXCEEDED",
      "NOT_FOUND",
      "ALREADY_EXISTS",
      "PERMISSION_DENIED",
      "RESOURCE_EXHAUSTED",
      "FAILED_PRECONDITION",
      "ABORTED",
      "OUT_OF_RANGE",
      "UNIMPLEMENTED",
      "INTERNAL",
      "UNAVAILABLE",
      "DATA_LOSS",
      "UNAUTHENTICATED",
    ]

    @Test(
      "Name",
      arguments: [
        ("method_config.name.full", MethodConfig.Name(service: "foo.bar", method: "baz")),
        ("method_config.name.service_only", MethodConfig.Name(service: "foo.bar", method: "")),
        ("method_config.name.empty", MethodConfig.Name(service: "", method: "")),
      ] as [(String, MethodConfig.Name)]
    )
    func name(_ fileName: String, expected: MethodConfig.Name) throws {
      let decoded = try self.decodeFromFile(fileName, as: MethodConfig.Name.self)
      #expect(decoded == expected)
    }

    @Test(
      "GoogleProtobufDuration",
      arguments: [
        ("1.0s", .seconds(1)),
        ("1s", .seconds(1)),
        ("1.000000s", .seconds(1)),
        ("0s", .zero),
        ("0.1s", .milliseconds(100)),
        ("100.123s", .milliseconds(100_123)),
      ] as [(String, Duration)]
    )
    func googleProtobufDuration(duration: String, expectedDuration: Duration) throws {
      let json = "\"\(duration)\""
      let decoded = try self.decodeFromJSONString(json, as: GoogleProtobufDuration.self)

      // Conversion is lossy as we go from floating point seconds to integer seconds and
      // attoseconds. Allow for millisecond precision.
      let divisor: Int64 = 1_000_000_000_000_000

      let duration = decoded.duration.components
      let expected = expectedDuration.components

      #expect(duration.seconds == expected.seconds)
      #expect(duration.attoseconds / divisor == expected.attoseconds / divisor)
    }

    @Test("Invalid GoogleProtobufDuration", arguments: ["1", "1ss", "1S", "1.0S"])
    func googleProtobufDuration(invalidDuration: String) throws {
      let json = "\"\(invalidDuration)\""
      #expect {
        try self.decodeFromJSONString(json, as: GoogleProtobufDuration.self)
      } throws: { error in
        guard let error = error as? RuntimeError else { return false }
        return error.code == .invalidArgument
      }
    }

    @Test("GoogleRPCCode from case name", arguments: zip(Self.codeNames, Status.Code.all))
    func rpcCode(name: String, expected: Status.Code) throws {
      let json = "\"\(name)\""
      let decoded = try self.decodeFromJSONString(json, as: GoogleRPCCode.self)
      #expect(decoded.code == expected)
    }

    @Test("GoogleRPCCode from rawValue", arguments: zip(0 ... 16, Status.Code.all))
    func rpcCode(rawValue: Int, expected: Status.Code) throws {
      let json = "\(rawValue)"
      let decoded = try self.decodeFromJSONString(json, as: GoogleRPCCode.self)
      #expect(decoded.code == expected)
    }

    @Test("RetryPolicy")
    func retryPolicy() throws {
      let decoded = try self.decodeFromFile("method_config.retry_policy", as: RetryPolicy.self)
      let expected = RetryPolicy(
        maxAttempts: 3,
        initialBackoff: .seconds(1),
        maxBackoff: .seconds(3),
        backoffMultiplier: 1.6,
        retryableStatusCodes: [.aborted, .unavailable]
      )
      #expect(decoded == expected)
    }

    @Test(
      "RetryPolicy with invalid values",
      arguments: [
        "method_config.retry_policy.invalid.backoff_multiplier",
        "method_config.retry_policy.invalid.initial_backoff",
        "method_config.retry_policy.invalid.max_backoff",
        "method_config.retry_policy.invalid.max_attempts",
        "method_config.retry_policy.invalid.retryable_status_codes",
      ]
    )
    func invalidRetryPolicy(fileName: String) throws {
      #expect(throws: RuntimeError.self) {
        try self.decodeFromFile(fileName, as: RetryPolicy.self)
      }
    }

    @Test("HedgingPolicy")
    func hedgingPolicy() throws {
      let decoded = try self.decodeFromFile("method_config.hedging_policy", as: HedgingPolicy.self)
      let expected = HedgingPolicy(
        maxAttempts: 3,
        hedgingDelay: .seconds(1),
        nonFatalStatusCodes: [.aborted]
      )
      #expect(decoded == expected)
    }

    @Test(
      "HedgingPolicy with invalid values",
      arguments: [
        "method_config.hedging_policy.invalid.max_attempts"
      ]
    )
    func invalidHedgingPolicy(fileName: String) throws {
      #expect(throws: RuntimeError.self) {
        try self.decodeFromFile(fileName, as: HedgingPolicy.self)
      }
    }

    @Test("MethodConfig")
    func methodConfig() throws {
      let expected = MethodConfig(
        names: [
          MethodConfig.Name(
            service: "echo.Echo",
            method: "Get"
          )
        ],
        waitForReady: true,
        timeout: .seconds(1),
        maxRequestMessageBytes: 1024,
        maxResponseMessageBytes: 2048
      )

      let decoded = try self.decodeFromFile("method_config", as: MethodConfig.self)
      #expect(decoded == expected)
    }

    @Test("MethodConfig with hedging")
    func methodConfigWithHedging() throws {
      let expected = MethodConfig(
        names: [
          MethodConfig.Name(
            service: "echo.Echo",
            method: "Get"
          )
        ],
        waitForReady: true,
        timeout: .seconds(1),
        maxRequestMessageBytes: 1024,
        maxResponseMessageBytes: 2048,
        executionPolicy: .hedge(
          HedgingPolicy(
            maxAttempts: 3,
            hedgingDelay: .seconds(42),
            nonFatalStatusCodes: [.aborted, .unimplemented]
          )
        )
      )

      let decoded = try self.decodeFromFile("method_config.with_hedging", as: MethodConfig.self)
      #expect(decoded == expected)
    }

    @Test("MethodConfig with retries")
    func methodConfigWithRetries() throws {
      let expected = MethodConfig(
        names: [
          MethodConfig.Name(
            service: "echo.Echo",
            method: "Get"
          )
        ],
        waitForReady: true,
        timeout: .seconds(1),
        maxRequestMessageBytes: 1024,
        maxResponseMessageBytes: 2048,
        executionPolicy: .retry(
          RetryPolicy(
            maxAttempts: 3,
            initialBackoff: .seconds(1),
            maxBackoff: .seconds(3),
            backoffMultiplier: 1.6,
            retryableStatusCodes: [.aborted, .unimplemented]
          )
        )
      )

      let decoded = try self.decodeFromFile("method_config.with_retries", as: MethodConfig.self)
      #expect(decoded == expected)
    }
  }

  @Suite("Round-trip tests")
  struct RoundTrip {
    private func decodeFromFile<Decoded: Decodable>(
      _ name: String,
      as: Decoded.Type
    ) throws -> Decoded {
      let input = Bundle.module.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Inputs"
      )

      let url = try #require(input)
      let data = try Data(contentsOf: url)

      let decoder = JSONDecoder()
      return try decoder.decode(Decoded.self, from: data)
    }

    private func decodeFromJSONString<Decoded: Decodable>(
      _ json: String,
      as: Decoded.Type
    ) throws -> Decoded {
      let data = Data(json.utf8)
      let decoder = JSONDecoder()
      return try decoder.decode(Decoded.self, from: data)
    }

    private func encodeToJSON(_ value: some Encodable) throws -> String {
      let encoder = JSONEncoder()
      let encoded = try encoder.encode(value)
      let json = String(decoding: encoded, as: UTF8.self)
      return json
    }

    private func roundTrip<T: Codable & Equatable>(type: T.Type = T.self, fileName: String) throws {
      let decoded = try self.decodeFromFile(fileName, as: T.self)
      let encoded = try self.encodeToJSON(decoded)
      let decodedAgain = try self.decodeFromJSONString(encoded, as: T.self)
      #expect(decoded == decodedAgain)
    }

    @Test(
      "MethodConfig",
      arguments: [
        "method_config",
        "method_config.with_retries",
        "method_config.with_hedging",
      ]
    )
    func roundTripCodingAndDecoding(fileName: String) throws {
      try self.roundTrip(type: MethodConfig.self, fileName: fileName)
    }
  }
}
