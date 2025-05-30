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
import GRPCCore
import XCTest

@available(gRPCSwift 2.0, *)
final class MethodConfigsTests: XCTestCase {
  func testGetConfigurationForKnownMethod() async throws {
    let policy = HedgingPolicy(
      maxAttempts: 10,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: []
    )
    let defaultConfiguration = MethodConfig(names: [], executionPolicy: .hedge(policy))
    var configurations = MethodConfigs()
    configurations.setDefaultConfig(defaultConfiguration)
    let descriptor = MethodDescriptor(fullyQualifiedService: "test", method: "first")
    let retryPolicy = RetryPolicy(
      maxAttempts: 10,
      initialBackoff: .seconds(1),
      maxBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let overrideConfiguration = MethodConfig(names: [], executionPolicy: .retry(retryPolicy))
    configurations[descriptor] = overrideConfiguration

    XCTAssertEqual(configurations[descriptor], overrideConfiguration)
  }

  func testGetConfigurationForUnknownMethodButServiceOverride() {
    let policy = HedgingPolicy(
      maxAttempts: 10,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: []
    )
    let defaultConfiguration = MethodConfig(names: [], executionPolicy: .hedge(policy))
    var configurations = MethodConfigs()
    configurations.setDefaultConfig(defaultConfiguration)
    let firstDescriptor = MethodDescriptor(fullyQualifiedService: "test", method: "")
    let retryPolicy = RetryPolicy(
      maxAttempts: 10,
      initialBackoff: .seconds(1),
      maxBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let overrideConfiguration = MethodConfig(names: [], executionPolicy: .retry(retryPolicy))
    configurations[firstDescriptor] = overrideConfiguration

    let secondDescriptor = MethodDescriptor(fullyQualifiedService: "test", method: "second")
    XCTAssertEqual(configurations[secondDescriptor], overrideConfiguration)
  }

  func testGetConfigurationForUnknownMethodDefaultValue() {
    let policy = HedgingPolicy(
      maxAttempts: 10,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: []
    )
    let defaultConfiguration = MethodConfig(names: [], executionPolicy: .hedge(policy))
    var configurations = MethodConfigs()
    configurations.setDefaultConfig(defaultConfiguration)
    let firstDescriptor = MethodDescriptor(fullyQualifiedService: "test1", method: "first")
    let retryPolicy = RetryPolicy(
      maxAttempts: 10,
      initialBackoff: .seconds(1),
      maxBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let overrideConfiguration = MethodConfig(names: [], executionPolicy: .retry(retryPolicy))
    configurations[firstDescriptor] = overrideConfiguration

    let secondDescriptor = MethodDescriptor(fullyQualifiedService: "test2", method: "second")
    XCTAssertEqual(configurations[secondDescriptor], defaultConfiguration)
  }
}
