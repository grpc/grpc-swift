// swift-tools-version:4.0
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

var packageDependencies: [Package.Dependency] = [
  .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMinor(from: "1.0.3")),
  .package(url: "https://github.com/kylef/Commander.git", from: "0.8.0"),
  .package(url: "https://github.com/apple/swift-nio-zlib-support.git", from: "1.0.0")
]

var cGRPCDependencies: [Target.Dependency] = []
#if os(Linux)
// On Linux, Foundation links with openssl, so we'll need to use that instead of BoringSSL.
// See https://github.com/apple/swift-nio-ssl/issues/16#issuecomment-392705505 for details.
packageDependencies.append(.package(url: "https://github.com/apple/swift-nio-ssl-support.git", from: "1.0.0"))
#else
cGRPCDependencies.append("BoringSSL")
#endif

let package = Package(
  name: "SwiftGRPC",
  products: [
    .library(name: "SwiftGRPC", targets: ["SwiftGRPC"]),
  ],
  dependencies: packageDependencies,
  targets: [
    .target(name: "SwiftGRPC",
            dependencies: ["CgRPC", "SwiftProtobuf"]),
    .target(name: "CgRPC",
            dependencies: cGRPCDependencies),
    .target(name: "RootsEncoder"),
    .target(name: "protoc-gen-swiftgrpc",
            dependencies: [
              "SwiftProtobuf",
              "SwiftProtobufPluginLibrary",
              "protoc-gen-swift"]),
    .target(name: "BoringSSL"),
    .target(name: "Echo",
            dependencies: [
              "SwiftGRPC",
              "SwiftProtobuf",
              "Commander"],
            path: "Sources/Examples/Echo"),
    .target(name: "Simple",
            dependencies: ["SwiftGRPC", "Commander"],
            path: "Sources/Examples/Simple"),
    .testTarget(name: "SwiftGRPCTests", dependencies: ["SwiftGRPC"])
  ],
  cLanguageStandard: .gnu11,
  cxxLanguageStandard: .cxx11)
