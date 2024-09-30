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
    request: ServerRequest.Single<Routeguide_Point>,
    context: ServerContext
  ) async throws -> ServerResponse.Single<Routeguide_Feature> {
  }

  func listFeatures(
    request: ServerRequest.Single<Routeguide_Rectangle>,
    context: ServerContext
  ) async throws -> ServerResponse.Stream<Routeguide_Feature> {
  }

  func recordRoute(
    request: ServerRequest.Stream<Routeguide_Point>,
    context: ServerContext
  ) async throws -> ServerResponse.Single<Routeguide_RouteSummary> {
  }

  func routeChat(
    request: ServerRequest.Stream<Routeguide_RouteNote>,
    context: ServerContext
  ) async throws -> ServerResponse.Stream<Routeguide_RouteNote> {
  }
}
