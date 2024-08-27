extension RouteGuide {
  func runServer() async throws {
    let features = try self.loadFeatures()
    let routeGuide = RouteGuideService(features: features)
  }
}
