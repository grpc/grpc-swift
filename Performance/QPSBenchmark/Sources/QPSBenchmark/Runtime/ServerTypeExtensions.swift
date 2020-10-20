/*
 * Copyright 2020, gRPC Authors All rights reserved.
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

extension Grpc_Testing_ServerType: CustomStringConvertible {
  /// Text descriptions for the server types.
  public var description: String {
    switch self {
    case .syncServer:
      return "syncServer"
    case .asyncServer:
      return "asyncServer"
    case .asyncGenericServer:
      return "asyncGenericServer"
    case .otherServer:
      return "otherServer"
    case .callbackServer:
      return "callbackServer"
    case let .UNRECOGNIZED(value):
      return "unrecognised\(value)"
    }
  }
}
