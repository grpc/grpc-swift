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
  .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMajor(from: "1.3.1")),

  // Command line argument parser for our auxiliary command line tools.
  .package(url: "https://github.com/kylef/Commander.git", .upToNextMinor(from: "0.8.0")),

  // SwiftGRPCNIO dependencies:
  // Main SwiftNIO package
  .package(url: "https://github.com/apple/swift-nio.git", from: "2.2.0"),
  // HTTP2 via SwiftNIO
  .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.2.0"),
  // TLS via SwiftNIO
  .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0"),
]

let package = Package(
  name: "SwiftGRPC",
  products: [
    .library(name: "SwiftGRPCNIO", targets: ["SwiftGRPCNIO"]),
  ],
  dependencies: packageDependencies,
  targets: [
    .target(name: "SwiftGRPCNIO",
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
    .target(name: "EchoNIO",
            dependencies: [
              "SwiftGRPCNIO",
              "SwiftGRPCNIOSampleData",
              "SwiftProtobuf",
              "Commander"],
            path: "Sources/Examples/EchoNIO"),
    .target(name: "SwiftGRPCNIOInteroperabilityTests",
            dependencies: ["SwiftGRPCNIO"]),
    .target(name: "SwiftGRPCNIOInteroperabilityTestsCLI",
            dependencies: [
              "SwiftGRPCNIOInteroperabilityTests",
              "Commander"]),
    .target(name: "SwiftGRPCNIOSampleData",
            dependencies: ["NIOSSL"]),
    .testTarget(name: "SwiftGRPCNIOTests",
                dependencies: [
                  "SwiftGRPCNIO",
                  "SwiftGRPCNIOSampleData",
                  "SwiftGRPCNIOInteroperabilityTests"]),
    .target(name: "SwiftGRPCNIOPerformanceTests",
            dependencies: [
              "SwiftGRPCNIO",
              "NIO",
              "NIOSSL",
              "Commander",
            ]),
  ])
