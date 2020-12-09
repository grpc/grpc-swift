// swift-tools-version:5.1
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
  products: [
    .executable(name: "QPSBenchmark", targets: ["QPSBenchmark"]),
  ],

  dependencies: [
    .package(path: "../../"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.22.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.4.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "0.3.0"),
    .package(
      url: "https://github.com/swift-server/swift-service-lifecycle.git",
      from: "1.0.0-alpha"
    ),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.9.0"),
  ],
  targets: [
    .target(name: "QPSBenchmark", dependencies: [
      "GRPC",
      "NIO",
      "ArgumentParser",
      "Logging",
      "Lifecycle",
      "SwiftProtobuf",
      "BenchmarkUtils",
    ]),
    .target(name: "BenchmarkUtils", dependencies: [
      "GRPC",
    ]),
    .testTarget(name: "BenchmarkUtilsTests", dependencies: [
      "GRPC",
      "BenchmarkUtils",
    ]),
  ]
)
