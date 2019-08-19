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

let package = Package(
  name: "GRPC",
  products: [
    .library(name: "GRPC", targets: ["GRPC"]),
    .executable(name: "InteroperabilityTestRunner", targets: ["GRPCInteroperabilityTests"]),
    .executable(name: "PerformanceTestRunner", targets: ["GRPCPerformanceTests"]),
    .executable(name: "Echo", targets: ["Echo"]),
  ],
  dependencies: [
    // GRPC dependencies:
    // Main SwiftNIO package
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.2.0"),
    // HTTP2 via SwiftNIO
    .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.5.0"),
    // TLS via SwiftNIO
    .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0"),
    // Support for Network.framework where possible. Note: from 1.0.2 the package
    // is essentially an empty import on platforms where it isn't supported.
    .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.0.2"),

    // Official SwiftProtobuf library, for [de]serializing data to send on the wire.
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.5.0"),

    // Logging API.
    .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),

    // Command line argument parser for our auxiliary command line tools.
    .package(url: "https://github.com/kylef/Commander.git", from: "0.8.0"),
  ],
  targets: [
    // The main GRPC module.
    .target(
      name: "GRPC",
      dependencies: [
        "NIO",
        "NIOFoundationCompat",
        "NIOTransportServices",
        "NIOHTTP1",
        "NIOHTTP2",
        "NIOSSL",
        "SwiftProtobuf",
        "Logging"
      ]
    ),  // and its tests.
    .testTarget(
      name: "GRPCTests",
      dependencies: [
        "GRPC",
        "GRPCSampleData",
        "GRPCInteroperabilityTestsImplementation"
      ]
    ),

    // The `protoc` plugin.
    .target(
      name: "protoc-gen-swiftgrpc",
      dependencies: [
        "SwiftProtobuf",
        "SwiftProtobufPluginLibrary",
        "protoc-gen-swift"
      ]
    ),

    // Interoperability tests implementation.
    .target(
      name: "GRPCInteroperabilityTestsImplementation",
      dependencies: [
        "GRPC",
        "GRPCInteroperabilityTestModels"
      ]
    ),

    // Generated interoperability test models.
    .target(
      name: "GRPCInteroperabilityTestModels",
      dependencies: [
        "GRPC",
        "NIO",
        "NIOHTTP1",
        "SwiftProtobuf"
      ]
    ),

    // The CLI for the interoperability tests.
    .target(
      name: "GRPCInteroperabilityTests",
      dependencies: [
        "GRPCInteroperabilityTestsImplementation",
        "Commander"
      ]
    ),

    // Performance tests implementation and CLI.
    .target(
      name: "GRPCPerformanceTests",
      dependencies: [
        "GRPC",
        "NIO",
        "NIOSSL",
        "Commander",
      ]
    ),

    // Sample data, used in examples and tests.
    .target(
      name: "GRPCSampleData",
      dependencies: ["NIOSSL"]
    ),

    // Echo example.
    .target(
      name: "Echo",
      dependencies: [
        "GRPC",
        "GRPCSampleData",
        "SwiftProtobuf",
        "Commander"
      ],
      path: "Sources/Examples/Echo"
    ),
  ]
)
