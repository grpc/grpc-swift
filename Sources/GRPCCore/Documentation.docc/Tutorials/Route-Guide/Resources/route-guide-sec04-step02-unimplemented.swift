import GRPCCore

struct RouteGuideService: Routeguide_RouteGuide.SimpleServiceProtocol {
  func getFeature(
    request: Routeguide_Point,
    context: ServerContext
  ) async throws -> Routeguide_Feature {
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
