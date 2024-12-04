// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RouteGuide",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/grpc/grpc-swift.git", from: "2.0.0-beta.1"),
    .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0-beta.1"),
    .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.0.0-beta.1"),
  ],
  targets: []
)
