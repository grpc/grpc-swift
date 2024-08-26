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
    try await self.recordRoute(using: routeGuide)
    try await self.routeChat(using: routeGuide)
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

  private func recordRoute(using routeGuide: Routeguide_RouteGuideClient) async throws {
    print("→ Calling 'RecordRoute'")

    let features = try self.loadFeatures()
    let pointsToVisit = 10

    let summary = try await routeGuide.recordRoute { writer in
      for _ in 0 ..< pointsToVisit {
        if let feature = features.randomElement() {
          try await writer.write(feature.location)
        }
      }
    }

    print(
      """
      Finished trip with \(summary.pointCount) points. Passed \(summary.featureCount) \
      features. Travelled \(summary.distance) meters. It took \(summary.elapsedTime) seconds.
      """
    )
  }

  private func routeChat(using routeGuide: Routeguide_RouteGuideClient) async throws {
    print("→ Calling 'RouteChat'")

    try await routeGuide.routeChat { writer in
      let notes: [(String, (Int32, Int32))] = [
        ("First message", (0, 0)),
        ("Second message", (0, 1)),
        ("Third message", (1, 0)),
        ("Fourth message", (1, 1)),
        ("Fifth message", (0, 0)),
      ]

      for (message, (lat, lon)) in notes {
        let note = Routeguide_RouteNote.with {
          $0.message = message
          $0.location.latitude = lat
          $0.location.longitude = lon
        }
        print("Sending message '\(message)' at (\(lat), \(lon))")
        try await writer.write(note)
      }
    } onResponse: { response in
      for try await note in response.messages {
        print(
          "Got message '\(note.message)' at (\(note.location.latitude), \(note.location.longitude))"
        )
      }
    }
  }
}
