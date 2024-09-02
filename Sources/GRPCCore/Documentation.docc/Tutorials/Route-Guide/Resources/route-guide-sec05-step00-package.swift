// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RouteGuide",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/grpc/grpc-swift", branch: "main"),
    .package(url: "https://github.com/apple/swift-protobuf", from: "1.27.0"),
  ],
  targets: [
    .executableTarget(
      name: "RouteGuide",
      dependencies: [
        .product(name: "_GRPCHTTP2Transport", package: "grpc-swift"),
        .product(name: "_GRPCProtobuf", package: "grpc-swift"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ]
    )
  ]
)
