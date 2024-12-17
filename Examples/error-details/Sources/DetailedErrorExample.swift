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

import GRPCCore
import GRPCInProcessTransport
import GRPCProtobuf

@main
struct DetailedErrorExample {
  static func main() async throws {
    let inProcess = InProcessTransport()
    try await withGRPCServer(transport: inProcess.server, services: [Greeter()]) { server in
      try await withGRPCClient(transport: inProcess.client) { client in
        try await Self.doRPC(Helloworld_Greeter.Client(wrapping: client))
      }
    }
  }

  static func doRPC(_ greeter: Helloworld_Greeter.Client) async throws {
    do {
      let reply = try await greeter.sayHello(.with { $0.name = "(ignored)" })
      print("Unexpected reply: \(reply.message)")
    } catch let error as RPCError {
      // Unpack the detailed from the standard 'RPCError'.
      guard let status = try error.unpackGoogleRPCStatus() else { return }
      print("Error code: \(status.code)")
      print("Error message: \(status.message)")
      print("Error details:")
      for detail in status.details {
        if let localizedMessage = detail.localizedMessage {
          print("- Localized message (\(localizedMessage.locale)): \(localizedMessage.message)")
        } else if let help = detail.help {
          print("- Help links:")
          for link in help.links {
            print("   - \(link.url) (\(link.linkDescription))")
          }
        }
      }
    }
  }
}

struct Greeter: Helloworld_Greeter.SimpleServiceProtocol {
  func sayHello(
    request: Helloworld_HelloRequest,
    context: ServerContext
  ) async throws -> Helloworld_HelloReply {
    // Always throw a detailed error.
    throw GoogleRPCStatus(
      code: .resourceExhausted,
      message: "The greeter has temporarily run out of greetings.",
      details: [
        .localizedMessage(
          locale: "en-GB",
          message: "Out of enthusiasm. The greeter is having a cup of tea, try again after that."
        ),
        .localizedMessage(
          locale: "en-US",
          message: "Out of enthusiasm. The greeter is taking a coffee break, try again later."
        ),
        .help(
          links: [
            ErrorDetails.Help.Link(
              url: "https://en.wikipedia.org/wiki/Caffeine",
              description: "A Wikipedia page about caffeine including its properties and effects."
            )
          ]
        ),
      ]
    )
  }
}
