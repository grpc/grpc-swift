// swift-tools-version:6.0
/*
 * Copyright 2025, gRPC Authors All rights reserved.
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
  name: "service-lifecycle",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/grpc/grpc-swift.git", from: "2.0.0"),
    .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0"),
    .package(url: "https://github.com/grpc/grpc-swift-extras", from: "1.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "service-lifecycle",
      dependencies: [
        .product(name: "GRPCCore", package: "grpc-swift"),
        .product(name: "GRPCInProcessTransport", package: "grpc-swift"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
        .product(name: "GRPCServiceLifecycle", package: "grpc-swift-extras"),
      ],
      plugins: [
        .plugin(name: "GRPCProtobufGenerator", package: "grpc-swift-protobuf")
      ]
    )
  ]
)
