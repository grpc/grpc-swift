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

/// A description of a service.
@available(gRPCSwift 2.0, *)
public struct ServiceDescriptor: Sendable, Hashable {
  /// The name of the package the service belongs to. For example, "helloworld".
  /// An empty string means that the service does not belong to any package.
  public var package: String {
    if let index = self.fullyQualifiedService.utf8.lastIndex(of: UInt8(ascii: ".")) {
      return String(self.fullyQualifiedService[..<index])
    } else {
      return ""
    }
  }

  /// The name of the service. For example, "Greeter".
  public var service: String {
    if var index = self.fullyQualifiedService.utf8.lastIndex(of: UInt8(ascii: ".")) {
      self.fullyQualifiedService.utf8.formIndex(after: &index)
      return String(self.fullyQualifiedService[index...])
    } else {
      return self.fullyQualifiedService
    }
  }

  /// The fully qualified service name in the format:
  /// - "package.service": if a package name is specified. For example, "helloworld.Greeter".
  /// - "service": if a package name is not specified. For example, "Greeter".
  public var fullyQualifiedService: String

  /// Create a new descriptor from the fully qualified service name.
  /// - Parameter fullyQualifiedService: The fully qualified service name.
  public init(fullyQualifiedService: String) {
    self.fullyQualifiedService = fullyQualifiedService
  }

  /// - Parameters:
  ///   - package: The name of the package the service belongs to. For example, "helloworld".
  ///   An empty string means that the service does not belong to any package.
  ///   - service: The name of the service. For example, "Greeter".
  public init(package: String, service: String) {
    if package.isEmpty {
      self.fullyQualifiedService = service
    } else {
      self.fullyQualifiedService = package + "." + service
    }
  }
}

@available(gRPCSwift 2.0, *)
extension ServiceDescriptor: CustomStringConvertible {
  public var description: String {
    self.fullyQualifiedService
  }
}
