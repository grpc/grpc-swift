// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RouteGuide",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/grpc/grpc-swift.git", from: "2.0.0-beta.3"),
    .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0-beta.3"),
    .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.0.0-beta.3"),
  ],
  targets: [
    .executableTarget(
      name: "RouteGuide",
      dependencies: [
        .product(name: "GRPCCore", package: "grpc-swift"),
        .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
      ],
      plugins: [
        .plugin(name: "GRPCProtobufGenerator", package: "grpc-swift-protobuf")
      ]
    )
  ]
)
