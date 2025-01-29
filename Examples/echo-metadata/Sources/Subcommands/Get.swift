/*
 * Copyright 2025, gRPC Authors All rights reserved.
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
import GRPCNIOTransportHTTP2

struct Get: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Makes a unary RPC to the echo-metadata server."
  )

  @OptionGroup
  var arguments: ClientArguments

  func run() async throws {
    try await withGRPCClient(
      transport: .http2NIOPosix(
        target: self.arguments.target,
        transportSecurity: .plaintext
      )
    ) { client in
      let echo = Echo_Echo.Client(wrapping: client)
      let requestMetadata: Metadata = ["echo-message": "\(arguments.message)"]
      let message = Echo_EchoRequest.with { $0.text = self.arguments.message }

      print("get → metadata: \(requestMetadata)")
      print("get → message: \(message.text)")
      try await echo.get(message, metadata: requestMetadata) { response in
        let initialMetadata = Metadata(response.metadata.filter({ $0.key.starts(with: "echo-") }))
        print("get ← initial metadata: \(initialMetadata)")
        print("get ← message: \(try response.message.text)")
        let trailingMetadata = Metadata(
          response.trailingMetadata.filter({ $0.key.starts(with: "echo-") })
        )
        print("get ← trailing metadata: \(trailingMetadata)")
      }
    }
  }
}
