/*
 * Copyright 2024, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import ArgumentParser
import Foundation
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import Synchronization

struct Serve: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Starts a route-guide server.")

  @Option(help: "The port to listen on")
  var port: Int = 31415

  private func loadFeatures() throws -> [Routeguide_Feature] {
    guard let url = Bundle.module.url(forResource: "route_guide_db", withExtension: "json") else {
      throw RPCError(code: .internalError, message: "Couldn't find 'route_guide_db.json")
    }

    let data = try Data(contentsOf: url)
    return try Routeguide_Feature.array(fromJSONUTF8Bytes: data)
  }

  func run() async throws {
    let features = try self.loadFeatures()
    let transport = HTTP2ServerTransport.Posix(
      address: .ipv4(host: "127.0.0.1", port: self.port),
      config: .defaults(transportSecurity: .plaintext)
    )

    let server = GRPCServer(transport: transport, services: [RouteGuideService(features: features)])
    try await withThrowingDiscardingTaskGroup { group in
      group.addTask { try await server.serve() }
      let address = try await transport.listeningAddress
      print("server listening on \(address)")
    }
  }
}

struct RouteGuideService {
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
}

extension RouteGuideService: Routeguide_RouteGuide.ServiceProtocol {
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
    return StreamingServerResponse { writer in
      let featuresWithinBounds = self.features.filter { feature in
        !feature.name.isEmpty && feature.isContained(by: request.message)
      }

      try await writer.write(contentsOf: featuresWithinBounds)
      return [:]
    }
  }

  func recordRoute(
    request: StreamingServerRequest<Routeguide_Point>,
    context: ServerContext
  ) async throws -> ServerResponse<Routeguide_RouteSummary> {
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

    return ServerResponse(message: summary)
  }

  func routeChat(
    request: StreamingServerRequest<Routeguide_RouteNote>,
    context: ServerContext
  ) async throws -> StreamingServerResponse<Routeguide_RouteNote> {
    return StreamingServerResponse { writer in
      for try await note in request.messages {
        let notes = self.receivedNotes.recordNote(note)
        try await writer.write(contentsOf: notes)
      }
      return [:]
    }
  }
}

extension Routeguide_Feature {
  func isContained(
    by rectangle: Routeguide_Rectangle
  ) -> Bool {
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
