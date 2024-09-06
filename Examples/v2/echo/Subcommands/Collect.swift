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

import ArgumentParser
import GRPCCore
import GRPCHTTP2Core
import GRPCHTTP2TransportNIOPosix

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct Collect: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Makes a client streaming RPC to the echo server."
  )

  @OptionGroup
  var arguments: ClientArguments

  func run() async throws {
    let client = GRPCClient(
      transport: try .http2NIOPosix(
        target: self.arguments.target,
        config: .defaults()
      )
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await client.run()
      }

      let echo = Echo_EchoClient(wrapping: client)

      for _ in 0 ..< self.arguments.repetitions {
        let message = try await echo.collect { writer in
          for part in self.arguments.message.split(separator: " ") {
            print("collect → \(part)")
            try await writer.write(.with { $0.text = String(part) })
          }
        }
        print("collect ← \(message.text)")
      }

      client.beginGracefulShutdown()
    }
  }
}
