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

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct Get: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Makes a unary RPC to the echo server.")

  @OptionGroup
  var arguments: ClientArguments

  func run() async throws {
    let transport = try HTTP2ClientTransport.Posix(target: self.arguments.target)
    let client = GRPCClient(transport: transport)

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await client.run()
      }

      let echo = Echo_EchoClient(client: client)

      for _ in 0 ..< self.arguments.repetitions {
        let message = Echo_EchoRequest.with { $0.text = self.arguments.message }
        print("get → \(message.text)")
        try await echo.get(request: ClientRequest.Single(message: message)) { response in
          let message = try response.message
          print("get ← \(message.text)")
        }
      }

      client.close()
    }
  }
}
