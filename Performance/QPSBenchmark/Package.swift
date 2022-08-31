// swift-tools-version:5.6
/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
  name: "QPSBenchmark",
  platforms: [.macOS(.v12)],
  products: [
    .executable(name: "QPSBenchmark", targets: ["QPSBenchmark"]),
  ],
  dependencies: [
    .package(path: "../../"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.41.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.4.3"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.1.1"),
    .package(url: "https://github.com/apple/swift-atomics.git", from: "1.0.2"),
    .package(
      url: "https://github.com/swift-server/swift-service-lifecycle.git",
      from: "1.0.0-alpha"
    ),
    .package(
      url: "https://github.com/apple/swift-protobuf.git",
      from: "1.20.1"
    ),
  ],
  targets: [
    .executableTarget(
      name: "QPSBenchmark",
      dependencies: [
        .product(name: "GRPC", package: "grpc-swift"),
        .product(name: "Atomics", package: "swift-atomics"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Lifecycle", package: "swift-service-lifecycle"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .target(name: "BenchmarkUtils"),
      ],
      plugins: [
        .plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf"),
        .plugin(name: "GRPCSwiftPlugin", package: "grpc-swift"),
      ]
    ),
    .target(
      name: "BenchmarkUtils",
      dependencies: [
        .product(name: "GRPC", package: "grpc-swift"),
      ]
    ),
    .testTarget(
      name: "BenchmarkUtilsTests",
      dependencies: [
        .product(name: "GRPC", package: "grpc-swift"),
        .target(name: "BenchmarkUtils"),
      ]
    ),
  ]
)
