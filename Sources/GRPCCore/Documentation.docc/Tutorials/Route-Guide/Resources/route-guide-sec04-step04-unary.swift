import GRPCCore

struct RouteGuideService: Routeguide_RouteGuide.SimpleServiceProtocol {
  /// Known features.
  private let features: [Routeguide_Feature]

  /// Creates a new route guide service.
  /// - Parameter features: Known features.
  init(features: [Routeguide_Feature]) {
    self.features = features
  }

  /// Returns the first feature found at the given location, if one exists.
  private func findFeature(latitude: Int32, longitude: Int32) -> Routeguide_Feature? {
    self.features.first {
      $0.location.latitude == latitude && $0.location.longitude == longitude
    }
  }

  func getFeature(
    request: Routeguide_Point,
    context: ServerContext
  ) async throws -> Routeguide_Feature {
    let feature = self.findFeature(
      latitude: request.message.latitude,
      longitude: request.message.longitude
    )
  }

  func listFeatures(
    request: Routeguide_Rectangle,
    response: RPCWriter<Routeguide_Feature>,
    context: ServerContext
  ) async throws {
  }

  func recordRoute(
    request: RPCAsyncSequence<Routeguide_Point, any Error>,
    context: ServerContext
  ) async throws -> Routeguide_RouteSummary {
  }

  func routeChat(
    request: RPCAsyncSequence<Routeguide_RouteNote, any Error>,
    response: RPCWriter<Routeguide_RouteNote>,
    context: ServerContext
  ) async throws {
  }
}
