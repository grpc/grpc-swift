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
import GRPCCore
import GRPCNIOTransportHTTP2

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
    try await withGRPCClient(
      transport: .http2NIOPosix(
        target: .ipv4(host: "127.0.0.1", port: self.port),
        transportSecurity: .plaintext
      )
    ) { client in
      let routeGuide = Routeguide_RouteGuide.Client(wrapping: client)

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
    }
  }
}
