import GRPCCore

struct RouteGuideService: Routeguide_RouteGuide.ServiceProtocol {
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
