import Foundation
import GRPCCore
import Synchronization

struct RouteGuideService: Routeguide_RouteGuide.ServiceProtocol {
  /// Known features.
  private let features: [Routeguide_Feature]

  /// Notes recorded by clients.
  private let receivedNotes: Notes

  /// A thread-safe store for notes sent by clients.
  private final class Notes: Sendable {
    private let notes: Mutex<[Routeguide_RouteNote]>

    init() {
      self.notes = Mutex([])
    }

    /// Records a note and returns all other notes recorded at the same location.
    ///
    /// - Parameter receivedNote: A note to record.
    /// - Returns: Other notes recorded at the same location.
    func recordNote(_ receivedNote: Routeguide_RouteNote) -> [Routeguide_RouteNote] {
      return self.notes.withLock { notes in
        var notesFromSameLocation: [Routeguide_RouteNote] = []
        for note in notes {
          if note.location == receivedNote.location {
            notesFromSameLocation.append(note)
          }
        }
        notes.append(receivedNote)
        return notesFromSameLocation
      }
    }
  }

  /// Creates a new route guide service.
  /// - Parameter features: Known features.
  init(features: [Routeguide_Feature]) {
    self.features = features
    self.receivedNotes = Notes()
  }

  /// Returns the first feature found at the given location, if one exists.
  private func findFeature(latitude: Int32, longitude: Int32) -> Routeguide_Feature? {
    self.features.first {
      $0.location.latitude == latitude && $0.location.longitude == longitude
    }
  }

  func getFeature(
    request: ServerRequest.Single<Routeguide_Point>,
    context: ServerContext
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
    request: ServerRequest.Single<Routeguide_Rectangle>,
    context: ServerContext
  ) async throws -> ServerResponse.Stream<Routeguide_Feature> {
    return ServerResponse.Stream { writer in
      for feature in self.features {
        if !feature.name.isEmpty, feature.isContained(by: request.message) {
          try await writer.write(feature)
        }
      }

      return [:]
    }
  }

  func recordRoute(
    request: ServerRequest.Stream<Routeguide_Point>,
    context: ServerContext
  ) async throws -> ServerResponse.Single<Routeguide_RouteSummary> {
    let startTime = ContinuousClock.now
    var pointsVisited = 0
    var featuresVisited = 0
    var distanceTravelled = 0.0
    var previousPoint: Routeguide_Point? = nil

    for try await point in request.messages {
      pointsVisited += 1

      if self.findFeature(latitude: point.latitude, longitude: point.longitude) != nil {
        featuresVisited += 1
      }

      if let previousPoint {
        distanceTravelled += greatCircleDistance(from: previousPoint, to: point)
      }

      previousPoint = point
    }

    let duration = startTime.duration(to: .now)
    let summary = Routeguide_RouteSummary.with {
      $0.pointCount = Int32(pointsVisited)
      $0.featureCount = Int32(featuresVisited)
      $0.elapsedTime = Int32(duration.components.seconds)
      $0.distance = Int32(distanceTravelled)
    }

    return ServerResponse.Single(message: summary)
  }

  func routeChat(
    request: ServerRequest.Stream<Routeguide_RouteNote>,
    context: ServerContext
  ) async throws -> ServerResponse.Stream<Routeguide_RouteNote> {
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

private func greatCircleDistance(
  from point1: Routeguide_Point,
  to point2: Routeguide_Point
) -> Double {
  // See https://en.wikipedia.org/wiki/Great-circle_distance
  //
  // Let λ1 (lambda1) and φ1 (phi1) be the longitude and latitude of point 1.
  // Let λ2 (lambda2) and φ2 (phi2) be the longitude and latitude of point 2.
  //
  // Let Δλ = λ2 - λ1, and Δφ = φ2 - φ1.
  //
  // The central angle between them, σc (sigmaC) can be computed as:
  //
  //   σc = 2 ⨯ sqrt(sin²(Δφ/2) + cos(φ1) ⨯ cos(φ2) ⨯ sin²(Δλ/2))
  //
  // The unit distance (d) between point1 and point2 can then be computed as:
  //
  //   d = 2 ⨯ atan(sqrt(σc), sqrt(1 - σc))

  let lambda1 = radians(degreesInE7: point1.longitude)
  let phi1 = radians(degreesInE7: point1.latitude)
  let lambda2 = radians(degreesInE7: point2.longitude)
  let phi2 = radians(degreesInE7: point2.latitude)

  // Δλ = λ2 - λ1
  let deltaLambda = lambda2 - lambda1
  // Δφ = φ2 - φ1
  let deltaPhi = phi2 - phi1

  // sin²(Δφ/2)
  let sinHalfDeltaPhiSquared = sin(deltaPhi / 2) * sin(deltaPhi / 2)
  // sin²(Δλ/2)
  let sinHalfDeltaLambdaSquared = sin(deltaLambda / 2) * sin(deltaLambda / 2)

  // σc = 2 ⨯ sqrt(sin²(Δφ/2) + cos(φ1) ⨯ cos(φ2) ⨯ sin²(Δλ/2))
  let sigmaC = 2 * sqrt(sinHalfDeltaPhiSquared + cos(phi1) * cos(phi2) * sinHalfDeltaLambdaSquared)

  // This is the unit distance, i.e. assumes the circle has a radius of 1.
  let unitDistance = 2 * atan2(sqrt(sigmaC), sqrt(1 - sigmaC))

  // Scale it by the radius of the Earth in meters.
  let earthRadius = 6_371_000.0
  return unitDistance * earthRadius
}

private func radians(degreesInE7 degrees: Int32) -> Double {
  return (Double(degrees) / 1e7) * .pi / 180.0
}
