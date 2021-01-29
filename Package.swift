// swift-tools-version:5.2
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

let package = Package(
  name: "grpc-swift",
  products: [
    .library(name: "GRPC", targets: ["GRPC"]),
    .library(name: "CGRPCZlib", targets: ["CGRPCZlib"]),
    .executable(name: "protoc-gen-grpc-swift", targets: ["protoc-gen-grpc-swift"]),
  ],
  dependencies: [
    // GRPC dependencies:
    // Main SwiftNIO package
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.22.0"),
    // HTTP2 via SwiftNIO
    .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.16.1"),
    // TLS via SwiftNIO
    .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.8.0"),
    // Support for Network.framework where possible.
    .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.6.0"),
    // Extra NIO stuff; quiescing helpers.
    .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.4.0"),

    // Official SwiftProtobuf library, for [de]serializing data to send on the wire.
    .package(
      name: "SwiftProtobuf",
      url: "https://github.com/apple/swift-protobuf.git",
      from: "1.9.0"
    ),

    // Logging API.
    .package(url: "https://github.com/apple/swift-log.git", from: "1.4.0"),

    // Argument parsering: only for internal targets (i.e. examples).
    // swift-argument-parser only provides source compatability guarantees between minor version.
    .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "0.3.0")),
  ],
  targets: [
    // The main GRPC module.
    .target(
      name: "GRPC",
      dependencies: [
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "NIOFoundationCompat", package: "swift-nio"),
        .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "NIOHTTP2", package: "swift-nio-http2"),
        .product(name: "NIOExtras", package: "swift-nio-extras"),
        .product(name: "NIOSSL", package: "swift-nio-ssl"),
        .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
        .product(name: "Logging", package: "swift-log"),
        .target(name: "CGRPCZlib"),
      ]
    ), // and its tests.
    .testTarget(
      name: "GRPCTests",
      dependencies: [
        .target(name: "GRPC"),
        .target(name: "EchoModel"),
        .target(name: "EchoImplementation"),
        .target(name: "GRPCSampleData"),
        .target(name: "GRPCInteroperabilityTestsImplementation"),
        .target(name: "HelloWorldModel"),
      ]
    ),

    .target(
      name: "CGRPCZlib",
      linkerSettings: [
        .linkedLibrary("z"),
      ]
    ),

    // The `protoc` plugin.
    .target(
      name: "protoc-gen-grpc-swift",
      dependencies: [
        .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
        .product(name: "SwiftProtobufPluginLibrary", package: "SwiftProtobuf"),
      ]
    ),

    // Interoperability tests implementation.
    .target(
      name: "GRPCInteroperabilityTestsImplementation",
      dependencies: [
        .target(name: "GRPC"),
        .target(name: "GRPCInteroperabilityTestModels"),
      ]
    ),

    // Generated interoperability test models.
    .target(
      name: "GRPCInteroperabilityTestModels",
      dependencies: [
        .target(name: "GRPC"),
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
      ]
    ),

    // The CLI for the interoperability tests.
    .target(
      name: "GRPCInteroperabilityTests",
      dependencies: [
        .target(name: "GRPCInteroperabilityTestsImplementation"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // The connection backoff interoperability test.
    .target(
      name: "GRPCConnectionBackoffInteropTest",
      dependencies: [
        .target(name: "GRPC"),
        .target(name: "GRPCInteroperabilityTestModels"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // Performance tests implementation and CLI.
    .target(
      name: "GRPCPerformanceTests",
      dependencies: [
        .target(name: "GRPC"),
        .target(name: "EchoModel"),
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // Sample data, used in examples and tests.
    .target(
      name: "GRPCSampleData",
      dependencies: [
        .product(name: "NIOSSL", package: "swift-nio-ssl"),
      ]
    ),

    // Echo example CLI.
    .target(
      name: "Echo",
      dependencies: [
        .target(name: "EchoModel"),
        .target(name: "EchoImplementation"),
        .target(name: "GRPC"),
        .target(name: "GRPCSampleData"),
        .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/Examples/Echo/Runtime"
    ),

    // Echo example service implementation.
    .target(
      name: "EchoImplementation",
      dependencies: [
        .target(name: "EchoModel"),
        .target(name: "GRPC"),
        .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
      ],
      path: "Sources/Examples/Echo/Implementation"
    ),

    // Model for Echo example.
    .target(
      name: "EchoModel",
      dependencies: [
        .target(name: "GRPC"),
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
      ],
      path: "Sources/Examples/Echo/Model"
    ),

    // Model for the HelloWorld example
    .target(
      name: "HelloWorldModel",
      dependencies: [
        .target(name: "GRPC"),
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
      ],
      path: "Sources/Examples/HelloWorld/Model"
    ),

    // Client for the HelloWorld example
    .target(
      name: "HelloWorldClient",
      dependencies: [
        .target(name: "GRPC"),
        .target(name: "HelloWorldModel"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/Examples/HelloWorld/Client"
    ),

    // Server for the HelloWorld example
    .target(
      name: "HelloWorldServer",
      dependencies: [
        .target(name: "GRPC"),
        .product(name: "NIO", package: "swift-nio"),
        .target(name: "HelloWorldModel"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/Examples/HelloWorld/Server"
    ),

    // Model for the RouteGuide example
    .target(
      name: "RouteGuideModel",
      dependencies: [
        .target(name: "GRPC"),
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
      ],
      path: "Sources/Examples/RouteGuide/Model"
    ),

    // Client for the RouteGuide example
    .target(
      name: "RouteGuideClient",
      dependencies: [
        .target(name: "GRPC"),
        .target(name: "RouteGuideModel"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/Examples/RouteGuide/Client"
    ),

    // Server for the RouteGuide example
    .target(
      name: "RouteGuideServer",
      dependencies: [
        .target(name: "GRPC"),
        .product(name: "NIO", package: "swift-nio"),
        .target(name: "RouteGuideModel"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/Examples/RouteGuide/Server"
    ),

    // Client for the PacketCapture example
    .target(
      name: "PacketCapture",
      dependencies: [
        .target(name: "GRPC"),
        .target(name: "EchoModel"),
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "NIOExtras", package: "swift-nio-extras"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/Examples/PacketCapture"
    ),
  ]
)
