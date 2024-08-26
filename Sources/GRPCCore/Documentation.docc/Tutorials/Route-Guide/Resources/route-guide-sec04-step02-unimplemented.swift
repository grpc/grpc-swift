import GRPCCore

struct RouteGuideService: Routeguide_RouteGuide.ServiceProtocol {
  func getFeature(
    request: ServerRequest.Single<Routeguide_Point>
  ) async throws -> ServerResponse.Single<Routeguide_Feature> {
  }

  func listFeatures(
    request: ServerRequest.Single<Routeguide_Rectangle>
  ) async throws -> ServerResponse.Stream<Routeguide_Feature> {
  }

  func recordRoute(
    request: ServerRequest.Stream<Routeguide_Point>
  ) async throws -> ServerResponse.Single<Routeguide_RouteSummary> {
  }

  func routeChat(
    request: ServerRequest.Stream<Routeguide_RouteNote>
  ) async throws -> ServerResponse.Stream<Routeguide_RouteNote> {
  }
}
