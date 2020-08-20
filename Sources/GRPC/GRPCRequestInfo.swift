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
struct GRPCRequestInfo: Equatable {
  let uri: String
  let service: Substring
  let method: Substring
}

extension GRPCRequestInfo {
  /// Split the given URI into a gRPC service and method.
  /// Returns `nil` if the URI is not in the correct format.
  ///
  /// - Parameter uri: The URI containing the gRPC request information.
  ///
  /// # URI Format
  /// "/package.Servicename/MethodName"
  init?(parsing uri: String) {
    let components = uri.split(separator: "/")
    guard components.count == 2 else { return nil }
    self.uri = uri
    self.service = components[0]
    self.method = components[1]
  }
}
