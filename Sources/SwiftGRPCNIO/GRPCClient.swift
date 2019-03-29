/*
 * Copyright 2019, gRPC Authors All rights reserved.
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

/// A GRPC client.
public protocol GRPCClient {
  /// The connection providing the underlying HTTP/2 channel for this client.
  var connection: GRPCClientConnection { get }

  /// The call options to use should the user not provide per-call options.
  var defaultCallOptions: CallOptions { get set }
}

/// A GRPC client for a named service.
public protocol GRPCServiceClient: GRPCClient {
  /// Name of the service this client is for (e.g. "echo.Echo").
  var serviceName: String { get }

  /// Creates a path for a given method on this service.
  ///
  /// This defaults to "/Service-Name/Method-Name" but may be overriden if consumers
  /// require a different path format.
  ///
  /// - Parameter method: name of method to return a path for.
  /// - Returns: path for the given method used in gRPC request headers.
  func path(forMethod method: String) -> String
}

extension GRPCServiceClient {
  public func path(forMethod method: String) -> String {
    return "/\(self.serviceName)/\(method)"
  }
}
