/*
 * Copyright 2023, gRPC Authors All rights reserved.
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
import EchoImplementation
import EchoModel
import Foundation
import GRPC
import GRPCReflectionService
import NIOPosix
import SwiftProtobuf

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@main
struct ReflectionServer: AsyncParsableCommand {
  @Option(help: "The port to listen on for new connections")
  var port = 1234

  func run() async throws {
    let group = MultiThreadedEventLoopGroup.singleton

    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let helloworldPath: String
    let echoPath: String

    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
      helloworldPath = url.appendingPathComponent("Generated/helloworld.grpc.reflection.txt").path()
      echoPath = url.appendingPathComponent("Generated/echo.grpc.reflection.txt").path()
    } else {
      helloworldPath = url.appendingPathComponent("Generated/helloworld.grpc.reflection.txt").path
      echoPath = url.appendingPathComponent("Generated/echo.grpc.reflection.txt").path
    }

    let reflectionService = try ReflectionService(
      serializedReflectionDataFilePaths: [helloworldPath, echoPath],
      version: .v1
    )

    // Start the server and print its address once it has started.
    let server = try await Server.insecure(group: group)
      .withServiceProviders([reflectionService, GreeterProvider(), EchoProvider()])
      .bind(host: "localhost", port: self.port)
      .get()

    print("server started on port \(server.channel.localAddress!.port!)")
    // Wait on the server's `onClose` future to stop the program from exiting.
    try await server.onClose.get()
  }
}
