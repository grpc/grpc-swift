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
import ArgumentParser
import Foundation
import GRPC
import Logging
import NIO
import RouteGuideModel

/// Makes a `RouteGuide` client for a service hosted on "localhost" and listening on the given port.
func makeClient(port: Int, group: EventLoopGroup) throws -> Routeguide_RouteGuideClient {
  let channel = try GRPCChannelPool.with(
    target: .host("localhost", port: port),
    transportSecurity: .plaintext,
    eventLoopGroup: group
  )

  return Routeguide_RouteGuideClient(channel: channel)
}

/// Unary call example. Calls `getFeature` and prints the response.
func getFeature(using client: Routeguide_RouteGuideClient, latitude: Int, longitude: Int) {
  print("→ GetFeature: lat=\(latitude) lon=\(longitude)")

  let point: Routeguide_Point = .with {
    $0.latitude = numericCast(latitude)
    $0.longitude = numericCast(longitude)
  }

  let call = client.getFeature(point)
  let feature: Routeguide_Feature

  do {
    feature = try call.response.wait()
  } catch {
    print("RPC failed: \(error)")
    return
  }

  let lat = feature.location.latitude
  let lon = feature.location.longitude

  if !feature.name.isEmpty {
    print("Found feature called '\(feature.name)' at \(lat), \(lon)")
  } else {
    print("Found no feature at \(lat), \(lon)")
  }
}

/// Server-streaming example. Calls `listFeatures` with a rectangle of interest. Prints each
/// response feature as it arrives.
func listFeatures(
  using client: Routeguide_RouteGuideClient,
  lowLatitude: Int,
  lowLongitude: Int,
  highLatitude: Int,
  highLongitude: Int
) {
  print(
    "→ ListFeatures: lowLat=\(lowLatitude) lowLon=\(lowLongitude), hiLat=\(highLatitude) hiLon=\(highLongitude)"
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

  var resultCount = 1
  let call = client.listFeatures(rectangle) { feature in
    print("Result #\(resultCount): \(feature)")
    resultCount += 1
  }

  let status = try! call.status.recover { _ in .processingError }.wait()
  if status.code != .ok {
    print("RPC failed: \(status)")
  }
}

/// Client-streaming example. Sends `featuresToVisit` randomly chosen points from `features` with
/// a variable delay in between. Prints the statistics when they are sent from the server.
public func recordRoute(
  using client: Routeguide_RouteGuideClient,
  features: [Routeguide_Feature],
  featuresToVisit: Int
) {
  print("→ RecordRoute")
  let options = CallOptions(timeLimit: .timeout(.minutes(1)))
  let call = client.recordRoute(callOptions: options)

  call.response.whenSuccess { summary in
    print(
      "Finished trip with \(summary.pointCount) points. Passed \(summary.featureCount) features. " +
        "Travelled \(summary.distance) meters. It took \(summary.elapsedTime) seconds."
    )
  }

  call.response.whenFailure { error in
    print("RecordRoute Failed: \(error)")
  }

  call.status.whenComplete { _ in
    print("Finished RecordRoute")
  }

  for _ in 0 ..< featuresToVisit {
    let index = Int.random(in: 0 ..< features.count)
    let point = features[index].location
    print("Visiting point \(point.latitude), \(point.longitude)")
    call.sendMessage(point, promise: nil)

    // Sleep for a bit before sending the next one.
    Thread.sleep(forTimeInterval: TimeInterval.random(in: 0.5 ..< 1.5))
  }

  call.sendEnd(promise: nil)

  // Wait for the call to end.
  _ = try! call.status.wait()
}

/// Bidirectional example. Send some chat messages, and print any chat messages that are sent from
/// the server.
func routeChat(using client: Routeguide_RouteGuideClient) {
  print("→ RouteChat")

  let call = client.routeChat { note in
    print(
      "Got message \"\(note.message)\" at \(note.location.latitude), \(note.location.longitude)"
    )
  }

  call.status.whenSuccess { status in
    if status.code == .ok {
      print("Finished RouteChat")
    } else {
      print("RouteChat Failed: \(status)")
    }
  }

  let noteContent = [
    ("First message", 0, 0),
    ("Second message", 0, 1),
    ("Third message", 1, 0),
    ("Fourth message", 1, 1),
  ]

  for (message, latitude, longitude) in noteContent {
    let note: Routeguide_RouteNote = .with {
      $0.message = message
      $0.location = .with {
        $0.latitude = Int32(latitude)
        $0.longitude = Int32(longitude)
      }
    }

    print(
      "Sending message \"\(note.message)\" at \(note.location.latitude), \(note.location.longitude)"
    )
    call.sendMessage(note, promise: nil)
  }
  // Mark the end of the stream.
  call.sendEnd(promise: nil)

  // Wait for the call to end.
  _ = try! call.status.wait()
}

/// Loads the features from `route_guide_db.json`, assumed to be in the directory above this file.
func loadFeatures() throws -> [Routeguide_Feature] {
  let url = URL(fileURLWithPath: #file)
    .deletingLastPathComponent() // main.swift
    .deletingLastPathComponent() // Client/
    .appendingPathComponent("route_guide_db.json")

  let data = try Data(contentsOf: url)
  return try Routeguide_Feature.array(fromJSONUTF8Data: data)
}

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

    // Make a client, make sure we close it when we're done.
    let routeGuide = try makeClient(port: self.port, group: group)
    defer {
      try? routeGuide.channel.close().wait()
    }

    // Look for a valid feature.
    getFeature(using: routeGuide, latitude: 409_146_138, longitude: -746_188_906)

    // Look for a missing feature.
    getFeature(using: routeGuide, latitude: 0, longitude: 0)

    // Looking for features between 40, -75 and 42, -73.
    listFeatures(
      using: routeGuide,
      lowLatitude: 400_000_000,
      lowLongitude: -750_000_000,
      highLatitude: 420_000_000,
      highLongitude: -730_000_000
    )

    // Record a few randomly selected points from the features file.
    recordRoute(using: routeGuide, features: features, featuresToVisit: 10)

    // Send and receive some notes.
    routeChat(using: routeGuide)
  }
}

RouteGuide.main()
