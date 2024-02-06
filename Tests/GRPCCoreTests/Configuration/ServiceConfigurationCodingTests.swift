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
import GRPCCore
import XCTest

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class ServiceConfigurationCodingTests: XCTestCase {
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

  private func testRoundTripEncodeDecode<C: Codable & Equatable>(_ value: C) throws {
    let encoded = try self.encoder.encode(value)
    let decoded = try self.decoder.decode(C.self, from: encoded)
    XCTAssertEqual(decoded, value)
  }

  func testDecodeRetryThrottlingPolicy() throws {
    let json = """
      {
        "maxTokens": 10,
        "tokenRatio": 0.5
      }
      """

    let expected = try ServiceConfiguration.RetryThrottlingPolicy(maxTokens: 10, tokenRatio: 0.5)
    let policy = try self.decoder.decode(
      ServiceConfiguration.RetryThrottlingPolicy.self,
      from: Data(json.utf8)
    )

    XCTAssertEqual(policy, expected)
  }

  func testEncodeDecodeRetryThrottlingPolicy() throws {
    let policy = try ServiceConfiguration.RetryThrottlingPolicy(maxTokens: 10, tokenRatio: 0.5)
    try self.testRoundTripEncodeDecode(policy)
  }

  func testDecodeRetryThrottlingPolicyWithInvalidTokens() throws {
    let inputs = ["0", "-1", "-42"]
    for input in inputs {
      let json = """
        {
          "maxTokens": \(input),
          "tokenRatio": 0.5
        }
        """

      try self.testDecodeThrowsRuntimeError(
        json: json,
        as: ServiceConfiguration.RetryThrottlingPolicy.self
      )
    }
  }

  func testDecodeRetryThrottlingPolicyWithInvalidTokenRatio() throws {
    let inputs = ["0.0", "-1.0", "-42"]
    for input in inputs {
      let json = """
        {
          "maxTokens": 10,
          "tokenRatio": \(input)
        }
        """

      try self.testDecodeThrowsRuntimeError(
        json: json,
        as: ServiceConfiguration.RetryThrottlingPolicy.self
      )
    }
  }

  func testDecodePickFirstPolicy() throws {
    let inputs: [(String, ServiceConfiguration.LoadBalancingConfiguration.PickFirst)] = [
      (#"{"shuffleAddressList": true}"#, .init(shuffleAddressList: true)),
      (#"{"shuffleAddressList": false}"#, .init(shuffleAddressList: false)),
      (#"{}"#, .init(shuffleAddressList: false)),
    ]

    for (input, expected) in inputs {
      let pickFirst = try self.decoder.decode(
        ServiceConfiguration.LoadBalancingConfiguration.PickFirst.self,
        from: Data(input.utf8)
      )

      XCTAssertEqual(pickFirst, expected)
    }
  }

  func testEncodePickFirstPolicy() throws {
    let inputs: [(ServiceConfiguration.LoadBalancingConfiguration.PickFirst, String)] = [
      (.init(shuffleAddressList: true), #"{"shuffleAddressList":true}"#),
      (.init(shuffleAddressList: false), #"{"shuffleAddressList":false}"#),
    ]

    for (input, expected) in inputs {
      let encoded = try self.encoder.encode(input)
      XCTAssertEqual(String(decoding: encoded, as: UTF8.self), expected)
    }
  }

  func testDecodeRoundRobinPolicy() throws {
    let json = "{}"
    let policy = try self.decoder.decode(
      ServiceConfiguration.LoadBalancingConfiguration.RoundRobin.self,
      from: Data(json.utf8)
    )
    XCTAssertEqual(policy, ServiceConfiguration.LoadBalancingConfiguration.RoundRobin())
  }

  func testEncodeRoundRobinPolicy() throws {
    let policy = ServiceConfiguration.LoadBalancingConfiguration.RoundRobin()
    let encoded = try self.encoder.encode(policy)
    XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "{}")
  }

  func testDecodeLoadBalancingConfiguration() throws {
    let inputs: [(String, ServiceConfiguration.LoadBalancingConfiguration)] = [
      (#"{"round_robin": {}}"#, .roundRobin),
      (#"{"pick_first": {}}"#, .pickFirst(shuffleAddressList: false)),
      (#"{"pick_first": {"shuffleAddressList": false}}"#, .pickFirst(shuffleAddressList: false)),
    ]

    for (input, expected) in inputs {
      let decoded = try self.decoder.decode(
        ServiceConfiguration.LoadBalancingConfiguration.self,
        from: Data(input.utf8)
      )
      XCTAssertEqual(decoded, expected)
    }
  }

  func testEncodeLoadBalancingConfiguration() throws {
    let inputs: [(ServiceConfiguration.LoadBalancingConfiguration, String)] = [
      (.roundRobin, #"{"round_robin":{}}"#),
      (.pickFirst(shuffleAddressList: false), #"{"pick_first":{"shuffleAddressList":false}}"#),
    ]

    for (input, expected) in inputs {
      let encoded = try self.encoder.encode(input)
      XCTAssertEqual(String(decoding: encoded, as: UTF8.self), expected)
    }
  }

  func testDecodeServiceConfigurationFromProtoJSON() throws {
    let serviceConfig = Grpc_ServiceConfig_ServiceConfig.with {
      $0.methodConfig = [
        Grpc_ServiceConfig_MethodConfig.with {
          $0.name = [
            Grpc_ServiceConfig_MethodConfig.Name.with {
              $0.service = "foo.Foo"
              $0.method = "Bar"
            }
          ]
          $0.timeout = .with { $0.seconds = 1 }
          $0.maxRequestMessageBytes = 123
          $0.maxResponseMessageBytes = 456
        }

      ]
      $0.loadBalancingConfig = [
        .with { $0.roundRobin = .init() },
        .with { $0.pickFirst = .with { $0.shuffleAddressList = true } },
      ]
      $0.retryThrottling = .with {
        $0.maxTokens = 10
        $0.tokenRatio = 0.1
      }
    }

    let encoded = try serviceConfig.jsonUTF8Data()
    let decoded = try self.decoder.decode(ServiceConfiguration.self, from: encoded)

    let expected = ServiceConfiguration(
      methodConfiguration: [
        MethodConfiguration(
          names: [
            MethodConfiguration.Name(service: "foo.Foo", method: "Bar")
          ],
          timeout: .seconds(1),
          maxRequestMessageBytes: 123,
          maxResponseMessageBytes: 456
        )
      ],
      loadBalancingConfiguration: [
        .roundRobin,
        .pickFirst(shuffleAddressList: true),
      ],
      retryThrottlingPolicy: try ServiceConfiguration.RetryThrottlingPolicy(
        maxTokens: 10,
        tokenRatio: 0.1
      )
    )

    XCTAssertEqual(decoded, expected)
  }

  func testEncodeAndDecodeServiceConfiguration() throws {
    let serviceConfig = ServiceConfiguration(
      methodConfiguration: [
        MethodConfiguration(
          names: [
            MethodConfiguration.Name(service: "echo.Echo", method: "Get"),
            MethodConfiguration.Name(service: "greeter.HelloWorld"),
          ],
          timeout: .seconds(42),
          maxRequestMessageBytes: 2048,
          maxResponseMessageBytes: 4096,
          executionPolicy: .hedge(
            HedgingPolicy(
              maximumAttempts: 3,
              hedgingDelay: .seconds(1),
              nonFatalStatusCodes: [.aborted]
            )
          )
        ),
        MethodConfiguration(
          names: [
            MethodConfiguration.Name(service: "echo.Echo", method: "Update")
          ],
          timeout: .seconds(300),
          maxRequestMessageBytes: 10_000
        ),
      ],
      loadBalancingConfiguration: [
        .pickFirst(shuffleAddressList: true),
        .roundRobin,
      ],
      retryThrottlingPolicy: try ServiceConfiguration.RetryThrottlingPolicy(
        maxTokens: 10,
        tokenRatio: 3.141
      )
    )

    try self.testRoundTripEncodeDecode(serviceConfig)
  }
}
