// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "PCAPExample",
  dependencies: [
    .package(path: "../../"),
    .package(url: "https://github.com/apple/swift-nio-extras", from: "1.4.0")
  ],
  targets: [
    .target(name: "PCAPExample", dependencies: ["GRPC", "NIOExtras"]),
  ]
)
