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
@main
struct HelloWorld: AsyncParsableCommand {
  @Option(help: "The port to listen on for new connections")
  var port = 1234

  func run() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      try! group.syncShutdownGracefully()
    }

    // Start the server and print its address once it has started.
    let server = try await Server.insecure(group: group)
      .withServiceProviders([GreeterProvider()])
      .bind(host: "localhost", port: self.port)
      .get()

    print("server started on port \(server.channel.localAddress!.port!)")

    // Wait on the server's `onClose` future to stop the program from exiting.
    try await server.onClose.get()
  }
}
#else
@main
enum HelloWorld {
  static func main() {
    fatalError("This example requires swift >= 5.6")
  }
}
#endif // compiler(>=5.6)
