import GRPCHTTP2Transport

extension RouteGuide {
  func runClient() async throws {
    let client = try GRPCClient(
      transport: .http2NIOPosix(
        target: .ipv4(host: "127.0.0.1", port: 31415),
        config: .defaults()
      )
    )

    async let _ = client.run()

    let routeGuide = Routeguide_RouteGuideClient(wrapping: client)
    try await self.getFeature(using: routeGuide)
    try await self.listFeatures(using: routeGuide)
  }

  private func getFeature(using routeGuide: Routeguide_RouteGuideClient) async throws {
    print("→ Calling 'GetFeature'")

    let point = Routeguide_Point.with {
      $0.latitude = 407_838_351
      $0.longitude = -746_143_763
    }

    let feature = try await routeGuide.getFeature(point)
    print("Got feature '\(feature.name)'")
  }

  private func listFeatures(using routeGuide: Routeguide_RouteGuideClient) async throws {
    print("→ Calling 'ListFeatures'")

    let boundingRectangle = Routeguide_Rectangle.with {
      $0.lo = .with {
        $0.latitude = 400_000_000
        $0.longitude = -750_000_000
      }
      $0.hi = .with {
        $0.latitude = 420_000_000
        $0.longitude = -730_000_000
      }
    }

    try await routeGuide.listFeatures(boundingRectangle) { response in
      for try await feature in response.messages {
        print(
          "Got feature '\(feature.name)' at (\(feature.location.latitude), \(feature.location.longitude))"
        )
      }
    }
  }
}
