# gRPC Swift

This repository contains a gRPC implementation for Swift. You can read more
about gRPC on the [gRPC project's website][grpcio].

- 📚 **Documentation** and **tutorials** are available on the [Swift Package Index][spi-grpc-swift]
- 💻 **Examples** are available in the [Examples](Examples) directory
- 🚀 **Contributions** are welcome, please see [CONTRIBUTING.md](CONTRIBUTING.md)
- 🪪 **License** is Apache 2.0, repeated in [LICENSE](License)
- 🔒 **Security** issues should be reported via the process in [SECURITY.md](SECURITY.md)
- 🔀 **Related Repositories**:
  - [`grpc-swift-nio-transport`][grpc-swift-nio-transport] contains high-performance HTTP/2 client and server transport implementations for gRPC Swift built on top of SwiftNIO.
  - [`grpc-swift-protobuf`][grpc-swift-protobuf] contains integrations with SwiftProtobuf for gRPC Swift.
  - [`grpc-swift-extras`][grpc-swift-extras] contains optional extras for gRPC Swift.


## Quick Start

The following snippet contains a Swift Package manifest to use gRPC Swift v2.x with
the SwiftNIO based transport and SwiftProtobuf serialization:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Application",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Server",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
            ]
        )
    ]
)
```

[gh-grpc]: https://github.com/grpc/grpc
[grpcio]: https://grpc.io
[spi-grpc-swift]: https://swiftpackageindex.com/grpc/grpc-swift/documentation
[grpc-swift-nio-transport]: https://github.com/grpc/grpc-swift-nio-transport
[grpc-swift-protobuf]: https://github.com/grpc/grpc-swift-protobuf
[grpc-swift-extras]: https://github.com/grpc/grpc-swift-extras
