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

import GRPCCore
import GRPCInProcessTransport
import GRPCServiceLifecycle
import Logging
import ServiceLifecycle

@main
struct LifecycleExample {
  static func main() async throws {
    // Create the gRPC service. It periodically changes the greeting returned to the client.
    // It also conforms to 'ServiceLifecycle.Service' and uses the 'run()' method to perform
    // the updates.
    //
    // A more realistic service may use the run method to maintain a connection to an upstream
    // service or database.
    let greetingService = GreetingService(updateInterval: .microseconds(250))

    // Create the client and server using the in-process transport (which is used here for
    // simplicity.)
    let inProcess = InProcessTransport()
    let server = GRPCServer(transport: inProcess.server, services: [greetingService])
    let client = GRPCClient(transport: inProcess.client)

    // Configure the service group with the services. They're started in the order they're listed
    // and shutdown in reverse order.
    let serviceGroup = ServiceGroup(
      services: [
        greetingService,
        server,
        client,
      ],
      logger: Logger(label: "io.grpc.examples.service-lifecycle")
    )

    try await withThrowingDiscardingTaskGroup { group in
      // Run the service group in a task group. This isn't typically required but is here in
      // order to make requests using the client while the service group is running.
      group.addTask {
        try await serviceGroup.run()
      }

      // Make some requests, pausing between each to give the server a chance to update
      // the greeting.
      let greeter = Helloworld_Greeter.Client(wrapping: client)
      for request in 1 ... 10 {
        let reply = try await greeter.sayHello(.with { $0.name = "request-\(request)" })
        print(reply.message)

        // Sleep for a moment.
        let waitTime = Duration.milliseconds((50 ... 400).randomElement()!)
        try await Task.sleep(for: waitTime)
      }

      // Finally, shutdown the service group gracefully.
      await serviceGroup.triggerGracefulShutdown()
    }
  }
}
