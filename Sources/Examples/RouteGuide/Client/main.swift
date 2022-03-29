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
#if compiler(>=5.6)
import ArgumentParser
import Foundation
import GRPC
import NIOCore
import NIOPosix
import RouteGuideModel

/// Loads the features from `route_guide_db.json`, assumed to be in the directory above this file.
func loadFeatures() throws -> [Routeguide_Feature] {
  let url = URL(fileURLWithPath: #file)
    .deletingLastPathComponent() // main.swift
    .deletingLastPathComponent() // Client/
    .appendingPathComponent("route_guide_db.json")

  let data = try Data(contentsOf: url)
  return try Routeguide_Feature.array(fromJSONUTF8Data: data)
}

/// Makes a `RouteGuide` client for a service hosted on "localhost" and listening on the given port.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
func makeClient(port: Int, group: EventLoopGroup) throws -> Routeguide_RouteGuideAsyncClient {
  let channel = try GRPCChannelPool.with(
    target: .host("localhost", port: port),
    transportSecurity: .plaintext,
    eventLoopGroup: group
  )

  return Routeguide_RouteGuideAsyncClient(channel: channel)
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal struct RouteGuideExample: @unchecked Sendable {
  private let routeGuide: Routeguide_RouteGuideAsyncClient
  private let features: [Routeguide_Feature]

  init(routeGuide: Routeguide_RouteGuideAsyncClient, features: [Routeguide_Feature]) {
    self.routeGuide = routeGuide
    self.features = features
  }

  func runAndBlockUntilCompletion() {
    let group = DispatchGroup()
    group.enter()

    Task {
      defer {
        group.leave()
      }

      // Look for a valid feature.
      await self.getFeature(latitude: 409_146_138, longitude: -746_188_906)

      // Look for a missing feature.
      await self.getFeature(latitude: 0, longitude: 0)

      // Looking for features between 40, -75 and 42, -73.
      await self.listFeatures(
        lowLatitude: 400_000_000,
        lowLongitude: -750_000_000,
        highLatitude: 420_000_000,
        highLongitude: -730_000_000
      )

      // Record a few randomly selected points from the features file.
      await self.recordRoute(features: features, featuresToVisit: 10)

      // Send and receive some notes.
      await self.routeChat()
    }

    group.wait()
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension RouteGuideExample {
  /// Get the feature at the given latitude and longitude, if one exists.
  private func getFeature(latitude: Int, longitude: Int) async {
    print("\n→ GetFeature: lat=\(latitude) lon=\(longitude)")

    let point: Routeguide_Point = .with {
      $0.latitude = numericCast(latitude)
      $0.longitude = numericCast(longitude)
    }

    do {
      let feature = try await self.routeGuide.getFeature(point)

      if !feature.name.isEmpty {
        print("Found feature called '\(feature.name)' at \(feature.location)")
      } else {
        print("Found no feature at \(feature.location)")
      }
    } catch {
      print("RPC failed: \(error)")
    }
  }

  /// List all features in the area bounded by the high and low latitude and longitudes.
  private func listFeatures(
    lowLatitude: Int,
    lowLongitude: Int,
    highLatitude: Int,
    highLongitude: Int
  ) async {
    print(
      "\n→ ListFeatures: lowLat=\(lowLatitude) lowLon=\(lowLongitude), hiLat=\(highLatitude) hiLon=\(highLongitude)"
    )

    let rectangle: Routeguide_Rectangle = .with {
      $0.lo = .with {
        $0.latitude = numericCast(lowLatitude)
        $0.longitude = numericCast(lowLongitude)
      }
      $0.hi = .with {
        $0.latitude = numericCast(highLatitude)
        $0.longitude = numericCast(highLongitude)
      }
    }

    do {
      var resultCount = 1
      for try await feature in self.routeGuide.listFeatures(rectangle) {
        print("Result #\(resultCount): \(feature)")
        resultCount += 1
      }
    } catch {
      print("RPC failed: \(error)")
    }
  }

  /// Record a route for `featuresToVisit` features selected randomly from `features` and print a
  /// summary of the route.
  private func recordRoute(
    features: [Routeguide_Feature],
    featuresToVisit: Int
  ) async {
    print("\n→ RecordRoute")
    let recordRoute = self.routeGuide.makeRecordRouteCall()

    do {
      for i in 1 ... featuresToVisit {
        if let feature = features.randomElement() {
          let point = feature.location
          print("Visiting point #\(i) at \(point)")
          try await recordRoute.requestStream.send(point)

          // Sleep for 0.2s ... 1.0s before sending the next point.
          try await Task.sleep(nanoseconds: UInt64.random(in: UInt64(2e8) ... UInt64(1e9)))
        }
      }

      try await recordRoute.requestStream.finish()
      let summary = try await recordRoute.response

      print(
        "Finished trip with \(summary.pointCount) points. Passed \(summary.featureCount) features. " +
          "Travelled \(summary.distance) meters. It took \(summary.elapsedTime) seconds."
      )
    } catch {
      print("RecordRoute Failed: \(error)")
    }
  }

  /// Record notes at given locations, printing each all other messages which have previously been
  /// recorded at the same location.
  private func routeChat() async {
    print("\n→ RouteChat")

    let notes = [
      ("First message", 0, 0),
      ("Second message", 0, 1),
      ("Third message", 1, 0),
      ("Fourth message", 1, 1),
    ].map { message, latitude, longitude in
      Routeguide_RouteNote.with {
        $0.message = message
        $0.location = .with {
          $0.latitude = Int32(latitude)
          $0.longitude = Int32(longitude)
        }
      }
    }

    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        let routeChat = self.routeGuide.makeRouteChatCall()

        // Add a task to send each message adding a small sleep between each.
        group.addTask {
          for note in notes {
            print("Sending message '\(note.message)' at \(note.location)")
            try await routeChat.requestStream.send(note)
            // Sleep for 0.2s ... 1.0s before sending the next note.
            try await Task.sleep(nanoseconds: UInt64.random(in: UInt64(2e8) ... UInt64(1e9)))
          }

          try await routeChat.requestStream.finish()
        }

        // Add a task to print each message received on the response stream.
        group.addTask {
          for try await note in routeChat.responseStream {
            print("Received message '\(note.message)' at \(note.location)")
          }
        }

        try await group.waitForAll()
      }
    } catch {
      print("RouteChat Failed: \(error)")
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct RouteGuide: ParsableCommand {
  @Option(help: "The port to connect to")
  var port: Int = 1234

  func run() throws {
    // Load the features.
    let features = try loadFeatures()

    let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
    defer {
      try? group.syncShutdownGracefully()
    }

    let routeGuide = try makeClient(port: self.port, group: group)
    defer {
      try? routeGuide.channel.close().wait()
    }

    // ArgumentParser did not support async/await at the point in time this was written. Block
    // this thread while the example runs.
    let example = RouteGuideExample(routeGuide: routeGuide, features: features)
    example.runAndBlockUntilCompletion()
  }
}

extension Routeguide_Point: CustomStringConvertible {
  public var description: String {
    return "(\(self.latitude), \(self.longitude))"
  }
}

extension Routeguide_Feature: CustomStringConvertible {
  public var description: String {
    return "\(self.name) at \(self.location)"
  }
}

if #available(macOS 12, *) {
  RouteGuide.main()
} else {
  fatalError("The RouteGuide example requires macOS 12 or newer.")
}
#else
fatalError("The RouteGuide example requires Swift concurrency features.")
#endif // compiler(>=5.6)
