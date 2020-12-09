// swift-tools-version:5.1
/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.7.0"),
    .package(url: "https://github.com/googleapis/google-auth-library-swift.git", from: "0.5.0"),
  ],
  targets: [
    .target(
      name: "NaturalLanguage",
      dependencies: [
        "GRPC",
        "SwiftProtobuf",
        "OAuth2",
      ],
      path: "Sources"
    ),
  ]
)
