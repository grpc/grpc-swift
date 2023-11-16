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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class ClientRPCExecutionConfigurationCollectionTests: XCTestCase {
  func testGetConfigurationForKnownMethod() {
    let policy = HedgingPolicy(
      maximumAttempts: 10,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: []
    )
    let defaultConfiguration = ClientRPCExecutionConfiguration(hedgingPolicy: policy)
    var configurations = ClientRPCExecutionConfigurationCollection(
      defaultConfiguration: defaultConfiguration
    )
    let descriptor = MethodDescriptor(service: "test", method: "first")
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let overrideConfiguration = ClientRPCExecutionConfiguration(retryPolicy: retryPolicy)
    configurations[descriptor] = overrideConfiguration

    XCTAssertEqual(configurations[descriptor], overrideConfiguration)
  }

  func testGetConfigurationForUnknownMethodButServiceOverride() {
    let policy = HedgingPolicy(
      maximumAttempts: 10,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: []
    )
    let defaultConfiguration = ClientRPCExecutionConfiguration(hedgingPolicy: policy)
    var configurations = ClientRPCExecutionConfigurationCollection(
      defaultConfiguration: defaultConfiguration
    )
    let firstDescriptor = MethodDescriptor(service: "test", method: "")
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let overrideConfiguration = ClientRPCExecutionConfiguration(retryPolicy: retryPolicy)
    configurations[firstDescriptor] = overrideConfiguration

    let secondDescriptor = MethodDescriptor(service: "test", method: "second")
    XCTAssertEqual(configurations[secondDescriptor], overrideConfiguration)
  }

  func testGetConfigurationForUnknownMethodDefaultValue() {
    let policy = HedgingPolicy(
      maximumAttempts: 10,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: []
    )
    let defaultConfiguration = ClientRPCExecutionConfiguration(hedgingPolicy: policy)
    var configurations = ClientRPCExecutionConfigurationCollection(
      defaultConfiguration: defaultConfiguration
    )
    let firstDescriptor = MethodDescriptor(service: "test1", method: "first")
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let overrideConfiguration = ClientRPCExecutionConfiguration(retryPolicy: retryPolicy)
    configurations[firstDescriptor] = overrideConfiguration

    let secondDescriptor = MethodDescriptor(service: "test2", method: "second")
    XCTAssertEqual(configurations[secondDescriptor], defaultConfiguration)
  }
}
