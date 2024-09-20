// swift-tools-version:6.0
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


import PackageDescription

let products: [Product] = [
  .library(
    name: "GRPCCore",
    targets: ["GRPCCore"]
  ),
  .library(
    name: "GRPCCodeGen",
    targets: ["GRPCCodeGen"]
  ),
  .library(
    name: "GRPCInProcessTransport",
    targets: ["GRPCInProcessTransport"]
  ),
]

let dependencies: [Package.Dependency] = [
  .package(
    url: "https://github.com/apple/swift-collections.git",
    from: "1.1.3"
  ),

  // Test-only dependencies:
  .package(
    url: "https://github.com/apple/swift-protobuf.git",
    from: "1.28.1"
  ),
]

let defaultSwiftSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault")
]

let targets: [Target] = [
  // Runtime serialization components
  .target(
    name: "GRPCCore",
    dependencies: [
      .product(name: "DequeModule", package: "swift-collections"),
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCCoreTests",
    dependencies: [
      .target(name: "GRPCCore"),
      .product(name: "SwiftProtobuf", package: "swift-protobuf")
    ],
    resources: [
      .copy("Configuration/Inputs")
    ]
  ),

  // In-process client and server transport implementations
  .target(
    name: "GRPCInProcessTransport",
    dependencies: [
      .target(name: "GRPCCore")
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCInProcessTransportTests",
    dependencies: [
      .target(name: "GRPCInProcessTransport")
    ]
  ),

  // Code generator library for protoc-gen-grpc-swift
  .target(
    name: "GRPCCodeGen",
    dependencies: [
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCCodeGenTests",
    dependencies: [
      .target(name: "GRPCCodeGen")
    ]
  )
]

let package = Package(
  name: "grpc-swift",
  products: products,
  dependencies: dependencies,
  targets: targets
)
