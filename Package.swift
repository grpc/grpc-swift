// swift-tools-version:5.0
/*
 * Copyright 2017, gRPC Authors All rights reserved.
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
import PackageDescription
import Foundation

var packageDependencies: [Package.Dependency] = [
  // Official SwiftProtobuf library, for [de]serializing data to send on the wire.
  .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.3.1"),

  // Command line argument parser for our auxiliary command line tools.
  .package(url: "https://github.com/kylef/Commander.git", .upToNextMinor(from: "0.8.0")),

  // GRPC dependencies:
  // Main SwiftNIO package
  .package(url: "https://github.com/apple/swift-nio.git", from: "2.2.0"),
  // HTTP2 via SwiftNIO
  .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.2.1"),
  // TLS via SwiftNIO
  .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0"),
]

let package = Package(
  name: "GRPC",
  products: [
    .library(name: "GRPC", targets: ["GRPC"]),
    .executable(name: "InteroperabilityTestRunner", targets: ["GRPCInteroperabilityTestsCLI"]),
    .executable(name: "PerformanceTestRunner", targets: ["GRPCPerformanceTests"]),
    .executable(name: "Echo", targets: ["Echo"]),
  ],
  dependencies: packageDependencies,
  targets: [
    .target(name: "GRPC",
            dependencies: [
              "NIO",
              "NIOFoundationCompat",
              "NIOHTTP1",
              "NIOHTTP2",
              "NIOSSL",
              "SwiftProtobuf"]),
    .target(name: "protoc-gen-swiftgrpc",
            dependencies: [
              "SwiftProtobuf",
              "SwiftProtobufPluginLibrary",
              "protoc-gen-swift"]),
    .target(name: "Echo",
            dependencies: [
              "GRPC",
              "GRPCSampleData",
              "SwiftProtobuf",
              "Commander"],
            path: "Sources/Examples/Echo"),
    .target(name: "GRPCInteroperabilityTests",
            dependencies: ["GRPC"]),
    .target(name: "GRPCInteroperabilityTestsCLI",
            dependencies: [
              "GRPCInteroperabilityTests",
              "Commander"]),
    .target(name: "GRPCSampleData",
            dependencies: ["NIOSSL"]),
    .testTarget(name: "GRPCTests",
                dependencies: [
                  "GRPC",
                  "GRPCSampleData",
                  "GRPCInteroperabilityTests"]),
    .target(name: "GRPCPerformanceTests",
            dependencies: [
              "GRPC",
              "NIO",
              "NIOSSL",
              "Commander",
            ]),
  ])
