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

struct ListFeatures: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List all features within a bounding rectangle."
  )

  @Option(help: "The server's listening port")
  var port: Int = 31415

  @Option(
    name: [.customLong("minimum-latitude"), .customLong("min-lat")],
    help: "Minimum latitude of the bounding rectangle to search in E7 format."
  )
  var minLatitude: Int32 = 400_000_000

  @Option(
    name: [.customLong("maximum-latitude"), .customLong("max-lat")],
    help: "Maximum latitude of the bounding rectangle to search in E7 format."
  )
  var maxLatitude: Int32 = 420_000_000

  @Option(
    name: [.customLong("minimum-longitude"), .customLong("min-lon")],
    help: "Minimum longitude of the bounding rectangle to search in E7 format."
  )
  var minLongitude: Int32 = -750_000_000

  @Option(
    name: [.customLong("maximum-longitude"), .customLong("max-lon")],
    help: "Maximum longitude of the bounding rectangle to search in E7 format."
  )
  var maxLongitude: Int32 = -730_000_000

  func run() async throws {
    try await withGRPCClient(
      transport: .http2NIOPosix(
        target: .ipv4(host: "127.0.0.1", port: self.port),
        transportSecurity: .plaintext
      )
    ) { client in
      let routeGuide = Routeguide_RouteGuide.Client(wrapping: client)
      let boundingRectangle = Routeguide_Rectangle.with {
        $0.lo.latitude = self.minLatitude
        $0.hi.latitude = self.maxLatitude
        $0.lo.longitude = self.minLongitude
        $0.hi.longitude = self.maxLongitude
      }

      try await routeGuide.listFeatures(boundingRectangle) { response in
        var count = 0
        for try await feature in response.messages {
          count += 1
          let (lat, lon) = (feature.location.latitude, feature.location.longitude)
          print("(\(count)) \(feature.name) at (\(lat), \(lon))")
        }
      }
    }
  }
}
