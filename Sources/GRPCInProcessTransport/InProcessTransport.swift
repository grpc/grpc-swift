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
import GRPCCore

public enum InProcessTransport {
  /// Returns a pair containing an ``InProcessServerTransport`` and an ``InProcessClientTransport``.
  ///
  /// This function is purely for convenience and does no more than constructing a server transport
  /// and a client using that server transport.
  ///
  /// - Parameters:
  ///   - serviceConfig: Configuration describing how methods should be executed.
  /// - Returns: A tuple containing the connected server and client in-process transports.
  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  public static func makePair(
    serviceConfig: ServiceConfig = ServiceConfig()
  ) -> (server: InProcessServerTransport, client: InProcessClientTransport) {
    let server = InProcessServerTransport()
    let client = InProcessClientTransport(
      server: server,
      serviceConfig: serviceConfig
    )
    return (server, client)
  }
}
