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
    request: ServerRequest.Single<Routeguide_Point>
  ) async throws -> ServerResponse.Single<Routeguide_Feature> {
    let feature = self.findFeature(
      latitude: request.message.latitude,
      longitude: request.message.longitude
    )

    if let feature {
      return ServerResponse.Single(message: feature)
    } else {
      // No feature: return a feature with an empty name.
      let unknownFeature = Routeguide_Feature.with {
        $0.name = ""
        $0.location = .with {
          $0.latitude = request.message.latitude
          $0.longitude = request.message.longitude
        }
      }
      return ServerResponse.Single(message: unknownFeature)
    }
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
