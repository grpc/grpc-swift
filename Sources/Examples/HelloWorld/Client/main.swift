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
#if compiler(>=5.6)
import ArgumentParser
import GRPC
import HelloWorldModel
import NIOCore
import NIOPosix

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct HelloWorld: AsyncParsableCommand {
  @Option(help: "The port to connect to")
  var port: Int = 1234

  @Argument(help: "The name to greet")
  var name: String?

  func run() async throws {
    // Setup an `EventLoopGroup` for the connection to run on.
    //
    // See: https://github.com/apple/swift-nio#eventloops-and-eventloopgroups
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    // Make sure the group is shutdown when we're done with it.
    defer {
      try! group.syncShutdownGracefully()
    }

    // Configure the channel, we're not using TLS so the connection is `insecure`.
    let channel = try GRPCChannelPool.with(
      target: .host("localhost", port: self.port),
      transportSecurity: .plaintext,
      eventLoopGroup: group
    )

    // Close the connection when we're done with it.
    defer {
      try! channel.close().wait()
    }

    // Provide the connection to the generated client.
    let greeter = Helloworld_GreeterAsyncClient(channel: channel)

    // Form the request with the name, if one was provided.
    let request = Helloworld_HelloRequest.with {
      $0.name = self.name ?? ""
    }

    do {
      let greeting = try await greeter.sayHello(request)
      print("Greeter received: \(greeting.message)")
    } catch {
      print("Greeter failed: \(error)")
    }
  }
}
#endif // compiler(>=5.6)
