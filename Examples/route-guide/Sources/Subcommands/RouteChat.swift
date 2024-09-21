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
import GRPCNIOTransportHTTP2

struct RouteChat: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: """
      Visits a few points and records a note at each, and prints all notes previously recorded at \
      each point.
      """
  )

  @Option(help: "The server's listening port")
  var port: Int = 31415

  func run() async throws {
    let transport = try HTTP2ClientTransport.Posix(
      target: .ipv4(host: "127.0.0.1", port: self.port),
      config: .defaults(transportSecurity: .plaintext)
    )
    let client = GRPCClient(transport: transport)

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await client.run()
      }

      let routeGuide = Routeguide_RouteGuideClient(wrapping: client)

      try await routeGuide.routeChat { writer in
        let notes: [(String, (Int32, Int32))] = [
          ("First message", (0, 0)),
          ("Second message", (0, 1)),
          ("Third message", (1, 0)),
          ("Fourth message", (0, 0)),
          ("Fifth message", (1, 0)),
        ]

        for (message, (lat, lon)) in notes {
          let note = Routeguide_RouteNote.with {
            $0.message = message
            $0.location.latitude = lat
            $0.location.longitude = lon
          }
          print("Sending note: '\(message) at (\(lat), \(lon))'")
          try await writer.write(note)
        }
      } onResponse: { response in
        for try await note in response.messages {
          let (lat, lon) = (note.location.latitude, note.location.longitude)
          print("Received note: '\(note.message) at (\(lat), \(lon))'")
        }
      }

      client.beginGracefulShutdown()
    }
  }
}
