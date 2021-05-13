// swift-tools-version:5.3
import PackageDescription

let package = Package(
  name: "grpc-swift-fuzzer",
  dependencies: [
    .package(name: "grpc-swift", path: ".."),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.27.0"),
  ],
  targets: [
    .target(
      name: "ServerFuzzer",
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
