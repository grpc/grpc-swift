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

struct Update: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Makes a bidirectional server streaming RPC to the echo-metadata server."
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

      print("update → metadata: \(requestMetadata)")
      try await echo.update(metadata: requestMetadata) { writer in
        for part in self.arguments.message.split(separator: " ") {
          print("update → message: \(part)")
          try await writer.write(.with { $0.text = String(part) })
        }
      } onResponse: { response in
        let responseContents = try response.accepted.get()

        let initialMetadata = Metadata(
          responseContents.metadata.filter({ $0.key.starts(with: "echo-") })
        )
        print("update ← initial metadata: \(initialMetadata)")
        for try await part in responseContents.bodyParts {
          switch part {
          case .message(let message):
            print("update ← message: \(message.text)")

          case .trailingMetadata(let trailingMetadata):
            let trailingMetadata = Metadata(
              trailingMetadata.filter({ $0.key.starts(with: "echo-") })
            )
            print("update ← trailing metadata: \(trailingMetadata)")
          }
        }
      }
    }
  }
}
