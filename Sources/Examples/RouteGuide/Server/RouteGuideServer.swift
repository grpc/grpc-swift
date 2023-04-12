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
import ArgumentParser
import struct Foundation.Data
import struct Foundation.URL
import GRPC
import NIOCore
import NIOPosix
import RouteGuideModel

/// Loads the features from `route_guide_db.json`, assumed to be in the directory above this file.
func loadFeatures() throws -> [Routeguide_Feature] {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // main.swift
    .deletingLastPathComponent() // Server/
    .appendingPathComponent("route_guide_db.json")

  let data = try Data(contentsOf: url)
  return try Routeguide_Feature.array(fromJSONUTF8Data: data)
}

@main
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct RouteGuide: AsyncParsableCommand {
  @Option(help: "The port to listen on for new connections")
  var port = 1234

  func run() async throws {
    // Create an event loop group for the server to run on.
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    defer {
      try! group.syncShutdownGracefully()
    }

    // Read the feature database.
    let features = try loadFeatures()

    // Create a provider using the features we read.
    let provider = RouteGuideProvider(features: features)

    // Start the server and print its address once it has started.
    let server = try await Server.insecure(group: group)
      .withServiceProviders([provider])
      .bind(host: "localhost", port: self.port)
      .get()

    print("server started on port \(server.channel.localAddress!.port!)")

    // Wait on the server's `onClose` future to stop the program from exiting.
    try await server.onClose.get()
  }
}
