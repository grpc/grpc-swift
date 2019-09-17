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
    .executable(name: "ConnectionBackoffInteropTestRunner", targets: ["GRPCConnectionBackoffInteropTest"]),
    .executable(name: "PerformanceTestRunner", targets: ["GRPCPerformanceTests"]),
    .executable(name: "Echo", targets: ["Echo"]),
    .executable(name: "protoc-gen-grpc-swift", targets: ["protoc-gen-grpc-swift"]),
  ],
  dependencies: [
    // GRPC dependencies:
    // Main SwiftNIO package
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.7.1"),
    // HTTP2 via SwiftNIO
    .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.5.0"),
    // TLS via SwiftNIO
    .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.4.0"),
    // Support for Network.framework where possible.
    .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.1.0"),

    // Official SwiftProtobuf library, for [de]serializing data to send on the wire.
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.5.0"),

    // Logging API.
    .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
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
        "EchoModel",
        "EchoImplementation",
        "GRPCSampleData",
        "GRPCInteroperabilityTestsImplementation"
      ]
    ),

    // The `protoc` plugin.
    .target(
      name: "protoc-gen-grpc-swift",
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
        "Logging",
      ]
    ),

    // The connection backoff interoperability test.
    .target(
      name: "GRPCConnectionBackoffInteropTest",
      dependencies: [
        "GRPC",
        "GRPCInteroperabilityTestModels",
        "Logging",
      ]
    ),

    // Performance tests implementation and CLI.
    .target(
      name: "GRPCPerformanceTests",
      dependencies: [
        "GRPC",
        "EchoModel",
        "EchoImplementation",
        "NIO",
        "NIOSSL",
      ]
    ),

    // Sample data, used in examples and tests.
    .target(
      name: "GRPCSampleData",
      dependencies: ["NIOSSL"]
    ),

    // Echo example CLI.
    .target(
      name: "Echo",
      dependencies: [
        "EchoModel",
        "EchoImplementation",
        "GRPC",
        "GRPCSampleData",
        "SwiftProtobuf",
      ],
      path: "Sources/Examples/Echo/Runtime"
    ),

    // Echo example service implementation.
    .target(
      name: "EchoImplementation",
      dependencies: [
        "EchoModel",
        "GRPC",
        "SwiftProtobuf"
      ],
      path: "Sources/Examples/Echo/Implementation"
    ),

    // Model for Echo example.
    .target(
      name: "EchoModel",
      dependencies: [
        "GRPC",
        "NIO",
        "NIOHTTP1",
        "SwiftProtobuf"
      ],
      path: "Sources/Examples/Echo/Model"
    ),
  ]
)
