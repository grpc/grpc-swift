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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct ClientRPCExecutionConfigurationCollection: Sendable, Hashable {
  private var elements: [MethodDescriptor: ClientRPCExecutionConfiguration]
  private let defaultConfiguration: ClientRPCExecutionConfiguration

  public init(
    defaultConfiguration: ClientRPCExecutionConfiguration = ClientRPCExecutionConfiguration(executionPolicy: nil, timeout: nil)
  ) {
    self.elements = [:]
    self.defaultConfiguration = defaultConfiguration
  }

  public subscript(_ descriptor: MethodDescriptor) -> ClientRPCExecutionConfiguration {
    get {
      if let methodLevelOverride = self.elements[descriptor] {
        return methodLevelOverride
      }
      var serviceLevelDescriptor = descriptor
      serviceLevelDescriptor.method = ""
      return self.elements[serviceLevelDescriptor, default: self.defaultConfiguration]
    }
    
    set {
      if descriptor.service.isEmpty {
        preconditionFailure("Method descriptor's service cannot be empty.")
      }
      self.elements[descriptor] = newValue
    }
  }
}
