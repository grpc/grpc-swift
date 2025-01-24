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

let package = Package(
  name: "error-details",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/grpc/grpc-swift.git", exact: "2.0.0-rc.1"),
    .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", exact: "1.0.0-rc.1"),
  ],
  targets: [
    .executableTarget(
      name: "error-details",
      dependencies: [
        .product(name: "GRPCCore", package: "grpc-swift"),
        .product(name: "GRPCInProcessTransport", package: "grpc-swift"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
      ],
      plugins: [
        .plugin(name: "GRPCProtobufGenerator", package: "grpc-swift-protobuf")
      ]
    )
  ]
)
