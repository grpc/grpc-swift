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

var packageDependencies: [Package.Dependency] = [
// Official SwiftProtobuf library, for [de]serializing data to send on the wire.
.package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMajor(from: "1.5.0")),

// Command line argument parser for our auxiliary command line tools.
.package(url: "https://github.com/kylef/Commander.git", .upToNextMinor(from: "0.8.0"))
]

let package = Package(
    name: "SwiftGRPC",
    products: [
        .library(name: "SwiftGRPC", targets: ["SwiftGRPC"])
    ],
    dependencies: packageDependencies,
    targets: [
        .target(name: "SwiftGRPC",
                dependencies: ["CgRPC", "SwiftProtobuf"]),
        .target(name: "CgRPC",
                dependencies: ["BoringSSL"],
                cSettings: [
                    .headerSearchPath("../BoringSSL/include"),
                    .unsafeFlags(["-Wno-module-import-in-extern-c"])],
                linkerSettings: [.linkedLibrary("z")]),
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
    swiftLanguageVersions: [.v4, .v4_2, .v5],
    cLanguageStandard: .gnu11,
    cxxLanguageStandard: .cxx11)
