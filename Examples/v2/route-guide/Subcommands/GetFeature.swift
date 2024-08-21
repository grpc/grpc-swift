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
struct GetFeature: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Gets a feature at a given location.")

  @Option(help: "The server's listening port")
  var port: Int = 31415

  @Option(
    name: [.customLong("latitude"), .customLong("lat")],
    help: "Latitude of the feature to get in E7 format (degrees ⨯ 1e7)"
  )
  var latitude: Int32 = 407_838_351

  @Option(
    name: [.customLong("longitude"), .customLong("lon")],
    help: "Longitude of the feature to get in E7 format (degrees ⨯ 1e7)"
  )
  var longitude: Int32 = -746_143_763

  func run() async throws {
    let transport = try HTTP2ClientTransport.Posix(
      target: .ipv4(host: "127.0.0.1", port: self.port)
    )
    let client = GRPCClient(transport: transport)

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await client.run()
      }

      let routeGuide = Routeguide_RouteGuideClient(wrapping: client)

      let point = Routeguide_Point.with {
        $0.latitude = self.latitude
        $0.longitude = self.longitude
      }

      let feature = try await routeGuide.getFeature(point)

      if feature.name.isEmpty {
        print("No feature found at (\(self.latitude), \(self.longitude))")
      } else {
        print("Found '\(feature.name)' at (\(self.latitude), \(self.longitude))")
      }

      client.close()
    }
  }
}
