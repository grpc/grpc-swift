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

/// A description of a method on a service.
public struct MethodDescriptor: Sendable, Hashable {
  /// The name of the service, including the package name.
  ///
  /// For example, the name of the "Greeter" service in "helloworld" package
  /// is "helloworld.Greeter".
  public var service: String

  /// The name of the method in the service, excluding the service name.
  public var method: String

  /// The fully qualified method name in the format "package.service/method".
  ///
  /// For example, the fully qualified name of the "SayHello" method of the "Greeter" service in
  /// "helloworld" package is "helloworld.Greeter/SayHelllo".
  public var fullyQualifiedMethod: String {
    "\(self.service)/\(self.method)"
  }

  /// Creates a new method descriptor.
  ///
  /// - Parameters:
  ///   - service: The name of the service, including the package name. For example,
  ///       "helloworld.Greeter".
  ///   - method: The name of the method. For example, "SayHello".
  public init(service: String, method: String) {
    self.service = service
    self.method = method
  }
}
