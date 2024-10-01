import GRPCCore

struct RouteGuideService: Routeguide_RouteGuide.ServiceProtocol {
  /// Known features.
  private let features: [Routeguide_Feature]

  /// Creates a new route guide service.
  /// - Parameter features: Known features.
  init(features: [Routeguide_Feature]) {
    self.features = features
  }

  func getFeature(
    request: ServerRequest<Routeguide_Point>,
    context: ServerContext
  ) async throws -> ServerResponse<Routeguide_Feature> {
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
