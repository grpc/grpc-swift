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

let package = Package(
  name: "NaturalLanguage",
  dependencies: [
    .package(url: "../../..", .branch("HEAD")),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.0.2"),
    .package(url: "https://github.com/kylef/Commander.git", from: "0.8.0"),
    .package(url: "https://github.com/google/auth-library-swift.git", from: "0.3.6")
  ],
  targets: [
    .target(name: "NaturalLanguage",
            dependencies: [
              "gRPC",
              "SwiftProtobuf",
              "Commander",
	            "OAuth2"
            ],
	    path: "Sources")
  ])
