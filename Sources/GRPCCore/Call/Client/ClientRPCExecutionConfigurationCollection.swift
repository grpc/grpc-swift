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
struct ClientRPCExecutionConfigurationCollection: ExpressibleByDictionaryLiteral {
  private var elements: [MethodDescriptor: ClientRPCExecutionConfiguration]
  private let defaultConfiguration: ClientRPCExecutionConfiguration
  
  init(defaultConfiguration: ClientRPCExecutionConfiguration) {
    self.elements = [:]
    self.defaultConfiguration = defaultConfiguration
  }
  
  init(dictionaryLiteral elements: (Key, Value)...) {
    elements.forEach({ (key, value) in
      self.elements[key] = value
    })
  }
  
  mutating func addConfiguration(_ configuration: ClientRPCExecutionConfiguration, forMethod descriptor: MethodDescriptor) {
    self.elements[descriptor] = configuration
  }
  
  func getConfiguration(forMethod descriptor: MethodDescriptor) -> ClientRPCExecutionConfiguration {
    self.elements[descriptor] ?? self.defaultConfiguration
  }
  
  subscript(_ descriptor: MethodDescriptor) -> ClientRPCExecutionConfiguration {
    self.getConfiguration(forMethod: descriptor)
  }
  
  
}
