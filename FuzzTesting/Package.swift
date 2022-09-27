// swift-tools-version:5.7
/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
  name: "grpc-swift-fuzzer",
  dependencies: [
    .package(name: "grpc-swift", path: ".."),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.27.0"),
  ],
  targets: [
    .executableTarget(
      name: "ServerFuzzer",
      dependencies: [
        .target(name: "ServerFuzzerLib"),
      ]
    ),
    .target(
      name: "ServerFuzzerLib",
      dependencies: [
        .product(name: "GRPC", package: "grpc-swift"),
        .product(name: "NIO", package: "swift-nio"),
        .target(name: "EchoImplementation"),
      ]
    ),
    .target(
      name: "EchoModel",
      dependencies: [
        .product(name: "GRPC", package: "grpc-swift"),
      ],
      exclude: [
        "echo.proto",
      ]
    ),
    .target(
      name: "EchoImplementation",
      dependencies: [
        .product(name: "GRPC", package: "grpc-swift"),
        .target(name: "EchoModel"),
      ]
    ),
  ]
)
