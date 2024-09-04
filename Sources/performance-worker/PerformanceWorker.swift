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

internal import ArgumentParser
private import GRPCCore
private import GRPCHTTP2Core
private import GRPCHTTP2TransportNIOPosix
private import NIOPosix

@main
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct PerformanceWorker: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "performance-worker",
      discussion: """
        This program starts a gRPC server running the 'worker' service. The worker service is \
        instructed by a driver program to become a benchmark client or a benchmark server.

        Typically at least two workers are started (at least one server and one client), and the \
        driver instructs benchmark clients to execute various scenarios against benchmark servers. \
        Results are reported back to the driver once scenarios have been completed.

        See https://grpc.io/docs/guides/benchmarking for more details.
        """
    )
  }

  @Option(
    name: .customLong("driver_port"),
    help: "Port to listen on for connections from the driver."
  )
  var driverPort: Int

  func run() async throws {
    debugOnly {
      print("[WARNING] performance-worker built in DEBUG mode, results won't be representative.")
    }

    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv4(host: "127.0.0.1", port: self.driverPort),
        config: .defaults(transportSecurity: .plaintext)
      ),
      services: [WorkerService()]
    )
    try await server.serve()
  }
}

private func debugOnly(_ body: () -> Void) {
  assert(alwaysTrue(body))
}

private func alwaysTrue(_ body: () -> Void) -> Bool {
  body()
  return true
}
