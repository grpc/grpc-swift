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

#if canImport(NIOSSL)
/// Application protocol identifiers for ALPN.
package enum GRPCApplicationProtocolIdentifier {
  static let gRPC = "grpc-exp"
  static let h2 = "h2"

  static func isHTTP2Like(_ value: String) -> Bool {
    switch value {
    case self.gRPC, self.h2:
      return true
    default:
      return false
    }
  }
}
#endif
