/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import GRPC
import HelloWorldModel
import Logging
import NIO

func greet(name: String?, client greeter: Helloworld_GreeterClient) {
  // Form the request with the name, if one was provided.
  let request = Helloworld_HelloRequest.with {
    $0.name = name ?? ""
  }

  // Make the RPC call to the server.
  let sayHello = greeter.sayHello(request)

  // wait() on the response to stop the program from exiting before the response is received.
  do {
    let response = try sayHello.response.wait()
    print("Greeter received: \(response.message)")
  } catch {
    print("Greeter failed: \(error)")
  }
}

func main(args: [String]) {
  // arg0 (dropped) is the program name. We expect arg1 to be the port, and arg2 (optional) to be
  // the name sent in the request.
  let arg1 = args.dropFirst(1).first
  let arg2 = args.dropFirst(2).first

  switch (arg1.flatMap(Int.init), arg2) {
  case (.none, _):
    print("Usage: PORT [NAME]")
    exit(1)

  case let (.some(port), name):
    // Setup an `EventLoopGroup` for the connection to run on.
    //
    // See: https://github.com/apple/swift-nio#eventloops-and-eventloopgroups
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    // Make sure the group is shutdown when we're done with it.
    defer {
      try! group.syncShutdownGracefully()
    }

    // Configure the channel, we're not using TLS so the connection is `insecure`.
    let channel = ClientConnection.insecure(group: group)
      .connect(host: "localhost", port: port)

    // Close the connection when we're done with it.
    defer {
      try! channel.close().wait()
    }

    // Provide the connection to the generated client.
    let greeter = Helloworld_GreeterClient(channel: channel)

    // Do the greeting.
    greet(name: name, client: greeter)
  }
}

main(args: CommandLine.arguments)
