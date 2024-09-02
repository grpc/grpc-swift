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
import GRPCHTTP2Transport

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct RecordRoute: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Records a route by visiting N randomly selected points and prints a summary of it."
  )

  @Option(help: "The server's listening port")
  var port: Int = 31415

  @Option(help: "The number of places to visit.")
  var points: Int = 10

  func run() async throws {
    let transport = try HTTP2ClientTransport.Posix(
      target: .ipv4(host: "127.0.0.1", port: self.port),
      config: .defaults()
    )
    let client = GRPCClient(transport: transport)

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await client.run()
      }

      let routeGuide = Routeguide_RouteGuideClient(wrapping: client)

      // Get all features.
      let rectangle = Routeguide_Rectangle.with {
        $0.lo.latitude = 400_000_000
        $0.hi.latitude = 420_000_000
        $0.lo.longitude = -750_000_000
        $0.hi.longitude = -730_000_000
      }
      let features = try await routeGuide.listFeatures(rectangle) { response in
        try await response.messages.reduce(into: []) { $0.append($1) }
      }

      // Pick 'N' locations to visit.
      let placesToVisit = features.shuffled().map { $0.location }.prefix(self.points)

      // Record a route.
      let summary = try await routeGuide.recordRoute { writer in
        try await writer.write(contentsOf: placesToVisit)
      }

      let text = """
        Visited \(summary.pointCount) points and \(summary.featureCount) features covering \
        a distance \(summary.distance) metres.
        """
      print(text)

      client.close()
    }
  }
}
