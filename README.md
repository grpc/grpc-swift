# gRPC Swift

This repository contains a gRPC implementation for Swift. You can read more
about gRPC on the [gRPC project's website][grpcio].

> gRPC Swift v2.x is under active development on the `main` branch and takes
> full advantage of Swift's native concurrency features.
>
> v1.x is still supported and maintained on the `release/1.x` branch.

- 📚 **Documentation** is available on the [Swift Package Index][spi-grpc-swift]
- 💻 **Examples** are available in the [Examples](Examples) directory
- 🚀 **Contributions** are welcome, please see [CONTRIBUTING.md](CONTRIBUTING.md)
- 🪪 **License** is Apache 2.0, repeated in [LICENSE](License)
- 🔒 **Security** issues should be reported via the process in [SECURITY.md](SECURITY.md)

## Quick Start

The following snippet contains a Swift Package manifest to use gRPC Swift v2.x with
the SwiftNIO based transport and SwiftProtobuf serialization:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "foo-package",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.0.0-alpha.1"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0-alpha.1"),
    ],
    targets: [
        .executableTarget(
            name: "bar-target",
            dependencies: [
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
