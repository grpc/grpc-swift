/*
 * Copyright 2021, gRPC Authors All rights reserved.
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

public struct GRPCServiceDescriptor: Hashable, GRPCSendable {
  /// The name of the service excluding the package, e.g. 'Echo'.
  public var name: String

  /// The full name of the service including the package, e.g. 'echo.Echo'
  public var fullName: String

  /// Methods defined on the service.
  public var methods: [GRPCMethodDescriptor]

  public init(name: String, fullName: String, methods: [GRPCMethodDescriptor]) {
    self.name = name
    self.fullName = fullName
    self.methods = methods
  }
}

public struct GRPCMethodDescriptor: Hashable, GRPCSendable {
  /// The name of the method, e.g. 'Get'.
  public var name: String

  /// The full name of the method include the fully qualified name of the service in the
  /// format 'package.Service/Method', for example 'echo.Echo/Get'.
  ///
  /// This differs from the ``path`` only in that the leading '/' is removed.
  public var fullName: String {
    assert(self.path.utf8.first == UInt8(ascii: "/"))
    return String(self.path.dropFirst())
  }

  /// The path of the method in the format '/package.Service/method', for example '/echo.Echo/Get'.
  public var path: String

  /// The type of call.
  public var type: GRPCCallType

  public init(name: String, path: String, type: GRPCCallType) {
    self.name = name
    self.path = path
    self.type = type
  }
}
