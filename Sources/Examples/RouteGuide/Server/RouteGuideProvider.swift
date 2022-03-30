/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
import GRPC
import NIOConcurrencyHelpers
import NIOCore
import RouteGuideModel

#if compiler(>=5.6)

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal final class RouteGuideProvider: Routeguide_RouteGuideAsyncProvider {
  private let features: [Routeguide_Feature]
  private let notes: Notes

  internal init(features: [Routeguide_Feature]) {
    self.features = features
    self.notes = Notes()
  }

  internal func getFeature(
    request point: Routeguide_Point,
    context: GRPCAsyncServerCallContext
  ) async throws -> Routeguide_Feature {
    return self.lookupFeature(at: point) ?? .unnamedFeature(at: point)
  }

  internal func listFeatures(
    request: Routeguide_Rectangle,
    responseStream: GRPCAsyncResponseStreamWriter<Routeguide_Feature>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    let longitudeRange = request.lo.longitude ... request.hi.longitude
    let latitudeRange = request.lo.latitude ... request.hi.latitude

    for feature in self.features where !feature.name.isEmpty {
      if feature.location.isWithin(latitude: latitudeRange, longitude: longitudeRange) {
        try await responseStream.send(feature)
      }
    }
  }

  internal func recordRoute(
    requestStream points: GRPCAsyncRequestStream<Routeguide_Point>,
    context: GRPCAsyncServerCallContext
  ) async throws -> Routeguide_RouteSummary {
    var pointCount: Int32 = 0
    var featureCount: Int32 = 0
    var distance = 0.0
    var previousPoint: Routeguide_Point?
    let startTimeNanos = DispatchTime.now().uptimeNanoseconds

    for try await point in points {
      pointCount += 1

      if let feature = self.lookupFeature(at: point), !feature.name.isEmpty {
        featureCount += 1
      }

      if let previous = previousPoint {
        distance += previous.distance(to: point)
      }

      previousPoint = point
    }

    let durationInNanos = DispatchTime.now().uptimeNanoseconds - startTimeNanos
    let durationInSeconds = Double(durationInNanos) / 1e9

    return .with {
      $0.pointCount = pointCount
      $0.featureCount = featureCount
      $0.elapsedTime = Int32(durationInSeconds)
      $0.distance = Int32(distance)
    }
  }

  internal func routeChat(
    requestStream: GRPCAsyncRequestStream<Routeguide_RouteNote>,
    responseStream: GRPCAsyncResponseStreamWriter<Routeguide_RouteNote>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for try await note in requestStream {
      let existingNotes = await self.notes.addNote(note, to: note.location)

      // Respond with all existing notes.
      for existingNote in existingNotes {
        try await responseStream.send(existingNote)
      }
    }
  }

  /// Returns a feature at the given location or an unnamed feature if none exist at that location.
  private func lookupFeature(at location: Routeguide_Point) -> Routeguide_Feature? {
    return self.features.first(where: {
      $0.location.latitude == location.latitude && $0.location.longitude == location.longitude
    })
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal final actor Notes {
  private var recordedNotes: [Routeguide_Point: [Routeguide_RouteNote]]

  internal init() {
    self.recordedNotes = [:]
  }

  /// Record a note at the given location and return the all notes which were previously recorded
  /// at the location.
  internal func addNote(
    _ note: Routeguide_RouteNote,
    to location: Routeguide_Point
  ) -> ArraySlice<Routeguide_RouteNote> {
    self.recordedNotes[location, default: []].append(note)
    return self.recordedNotes[location]!.dropLast(1)
  }
}

#endif // compiler(>=5.6)

private func degreesToRadians(_ degrees: Double) -> Double {
  return degrees * .pi / 180.0
}

extension Routeguide_Point {
  fileprivate func distance(to other: Routeguide_Point) -> Double {
    // Radius of Earth in meters
    let radius = 6_371_000.0
    // Points are in the E7 representation (degrees multiplied by 10**7 and rounded to the nearest
    // integer). See also `Routeguide_Point`.
    let coordinateFactor = 1.0e7

    let lat1 = degreesToRadians(Double(self.latitude) / coordinateFactor)
    let lat2 = degreesToRadians(Double(other.latitude) / coordinateFactor)
    let lon1 = degreesToRadians(Double(self.longitude) / coordinateFactor)
    let lon2 = degreesToRadians(Double(other.longitude) / coordinateFactor)

    let deltaLat = lat2 - lat1
    let deltaLon = lon2 - lon1

    let a = sin(deltaLat / 2) * sin(deltaLat / 2)
      + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))

    return radius * c
  }

  func isWithin<Range: RangeExpression>(
    latitude: Range,
    longitude: Range
  ) -> Bool where Range.Bound == Int32 {
    return latitude.contains(self.latitude) && longitude.contains(self.longitude)
  }
}

extension Routeguide_Feature {
  static func unnamedFeature(at location: Routeguide_Point) -> Routeguide_Feature {
    return .with {
      $0.name = ""
      $0.location = location
    }
  }
}
