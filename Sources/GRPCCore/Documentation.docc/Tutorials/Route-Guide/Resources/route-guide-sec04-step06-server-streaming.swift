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

    if let feature {
      return feature
    } else {
      // No feature: return a feature with an empty name.
      let unknownFeature = Routeguide_Feature.with {
        $0.name = ""
        $0.location = .with {
          $0.latitude = request.message.latitude
          $0.longitude = request.message.longitude
        }
      }
      return unknownFeature
    }
  }

  func listFeatures(
    request: Routeguide_Rectangle,
    response: RPCWriter<Routeguide_Feature>,
    context: ServerContext
  ) async throws {
    for feature in self.features {
      if !feature.name.isEmpty, feature.isContained(by: request) {
        try await response.write(feature)
      }
    }
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

extension Routeguide_Feature {
  func isContained(by rectangle: Routeguide_Rectangle) -> Bool {
    return rectangle.lo.latitude <= self.location.latitude
      && self.location.latitude <= rectangle.hi.latitude
      && rectangle.lo.longitude <= self.location.longitude
      && self.location.longitude <= rectangle.hi.longitude
  }
}
