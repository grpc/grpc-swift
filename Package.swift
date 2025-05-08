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

import CompilerPluginSupport
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

// -------------------------------------------------------------------------------------------------

// This adds some build settings which allow us to map "@available(gRPCSwift 2.x, *)" to
// the appropriate OS platforms.
let nextMinorVersion = 2
let availabilitySettings: [SwiftSetting] = (0 ... nextMinorVersion).map { minor in
  let name = "gRPCSwift"
  let version = "2.\(minor)"
  let platforms = "macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"
  let setting = "AvailabilityMacro=\(name) \(version):\(platforms)"
  return .enableExperimentalFeature(setting)
}

let defaultSwiftSettings: [SwiftSetting] =
  availabilitySettings + [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
  ]

// -------------------------------------------------------------------------------------------------

let targets: [Target] = [
  // Runtime serialization components
  .target(
    name: "GRPCCore",
    dependencies: [
      .product(name: "DequeModule", package: "swift-collections")
    ],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCCoreTests",
    dependencies: [
      .target(name: "GRPCCore"),
      .target(name: "GRPCInProcessTransport"),
      .product(name: "SwiftProtobuf", package: "swift-protobuf"),
    ],
    resources: [
      .copy("Configuration/Inputs")
    ],
    swiftSettings: defaultSwiftSettings
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
    ],
    swiftSettings: defaultSwiftSettings
  ),

  // Code generator library for protoc-gen-grpc-swift
  .target(
    name: "GRPCCodeGen",
    dependencies: [],
    swiftSettings: defaultSwiftSettings
  ),
  .testTarget(
    name: "GRPCCodeGenTests",
    dependencies: [
      .target(name: "GRPCCodeGen")
    ],
    swiftSettings: defaultSwiftSettings
  ),
]

let package = Package(
  name: "grpc-swift",
  products: products,
  dependencies: dependencies,
  targets: targets
)
