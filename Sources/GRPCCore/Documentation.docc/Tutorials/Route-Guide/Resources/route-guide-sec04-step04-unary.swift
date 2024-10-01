import GRPCCore

struct RouteGuideService: Routeguide_RouteGuide.ServiceProtocol {
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
    request: ServerRequest<Routeguide_Point>,
    context: ServerContext
  ) async throws -> ServerResponse<Routeguide_Feature> {
    let feature = self.findFeature(
      latitude: request.message.latitude,
      longitude: request.message.longitude
    )
  }

  func listFeatures(
    request: ServerRequest<Routeguide_Rectangle>,
    context: ServerContext
  ) async throws -> StreamingServerResponse<Routeguide_Feature> {
  }

  func recordRoute(
    request: StreamingServerRequest<Routeguide_Point>,
    context: ServerContext
  ) async throws -> ServerResponse<Routeguide_RouteSummary> {
  }

  func routeChat(
    request: StreamingServerRequest<Routeguide_RouteNote>,
    context: ServerContext
  ) async throws -> StreamingServerResponse<Routeguide_RouteNote> {
  }
}
