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

struct Echo: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract:
      "Makes a unary RPC to the echo-metadata server, followed by a bidirectional-streaming request."
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

      var requestMetadata: Metadata = [:]
      for metadataPair in arguments.metadata {
        guard metadataPair.starts(with: "echo-") else {
          continue
        }

        let pair = metadataPair.split(separator: "=")
        if pair.count == 2, let key = pair.first.map(String.init),
          let value = pair.last.map(String.init)
        {
          requestMetadata.addString(value, forKey: key)
        }
      }

      print("unary → \(requestMetadata)")
      try await echo.get(
        Echo_EchoRequest(),
        metadata: requestMetadata
      ) { response in
        print("unary ← Initial metadata: \(response.metadata.echoPairs)")
        print("unary ← Trailing metadata: \(response.trailingMetadata)")
      }

      print("bidirectional → \(requestMetadata)")
      try await echo.update(
        request: .init(
          metadata: requestMetadata,
          producer: { _ in }
        )
      ) { response in
        print("bidirectional ← Initial metadata: \(response.metadata.echoPairs)")
        for try await part in try response.accepted.get().bodyParts {
          switch part {
          case .trailingMetadata(let trailingMetadata):
            print("bidirectional ← Trailing metadata: \(trailingMetadata.echoPairs)")

          case .message:
            ()
          }
        }
      }
    }
  }
}
