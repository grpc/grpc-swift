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

    if let feature {
      return ServerResponse(message: feature)
    } else {
      // No feature: return a feature with an empty name.
      let unknownFeature = Routeguide_Feature.with {
        $0.name = ""
        $0.location = .with {
          $0.latitude = request.message.latitude
          $0.longitude = request.message.longitude
        }
      }
      return ServerResponse(message: unknownFeature)
    }
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
