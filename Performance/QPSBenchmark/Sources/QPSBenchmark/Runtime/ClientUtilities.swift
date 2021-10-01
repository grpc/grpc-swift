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

import GRPC
import NIOCore

/// Pair of host and port.
struct HostAndPort {
  /// The name of a host.
  var host: String
  /// A port on that host.
  var port: Int
}

extension Grpc_Testing_ClientConfig {
  /// Work out how many theads to use - defaulting to core count if not specified.
  /// - returns: The number of threads to use.
  func threadsToUse() -> Int {
    return self.asyncClientThreads > 0 ? Int(self.asyncClientThreads) : System.coreCount
  }

  /// Get the server targets parsed into a useful format.
  /// - returns: Server targets as hosts and ports.
  func parsedServerTargets() throws -> [HostAndPort] {
    let serverTargets = self.serverTargets
    return try serverTargets.map { target in
      if let splitIndex = target.lastIndex(of: ":") {
        let host = target[..<splitIndex]
        let portString = target[(target.index(after: splitIndex))...]
        if let port = Int(portString) {
          return HostAndPort(host: String(host), port: port)
        }
      }
      throw GRPCStatus(code: .invalidArgument, message: "Server targets could not be parsed")
    }
  }
}
