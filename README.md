[![Build Status](https://travis-ci.org/grpc/grpc-swift.svg?branch=master)](https://travis-ci.org/grpc/grpc-swift)
[![sswg:sandbox|94x20](https://img.shields.io/badge/sswg-sandbox-lightgrey.svg)](https://github.com/swift-server/sswg/blob/master/process/incubation.md#sandbox-level)

# gRPC Swift

This repository contains a gRPC Swift API and code generator.

It is intended for use with Apple's [SwiftProtobuf][swift-protobuf] support for
Protocol Buffers. Both projects contain code generation plugins for `protoc`,
Google's Protocol Buffer compiler, and both contain libraries of supporting code
that is needed to build and run the generated code.

APIs and generated code is provided for both gRPC clients and servers, and can
be built either with Xcode or the Swift Package Manager. Support is provided for
all four gRPC API styles (Unary, Server Streaming, Client Streaming, and
Bidirectional Streaming) and connections can be made either over secure (TLS) or
insecure channels.

gRPC Swift is built on top of [Swift NIO][swift-nio] as opposed to the core
library provided by the [gRPC project][grpc].

## Supported Platforms

gRPC Swift's platform support is identical to the [platform support of Swift
NIO][swift-nio-platforms].

Note that gRPC Swift uses NIO 2 and therefore requires Swift to be version 5.0
or higher.

## Getting gRPC Swift

There are two parts to gRPC Swift: the gRPC library and an API code generator.

### Getting the gRPC library

#### Swift Package Manager

The Swift Package Manager is the preferred way to get gRPC Swift. Simply add the
package dependency to your `Package.swift` and depend on `"GRPC"` in the
necessary targets:

```swift
dependencies: [
  .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.0.0-alpha.9")
]
```

The syntax for target dependencies changed in Swift 5.2 and requires the package
of each dependency to be specified.

For Swift 5.2 (`swift-tools-version:5.2`):

```swift
.target(
  name: ...,
  dependencies: [.product(name: "GRPC", package: "grpc-swift")]
)
```

For Swift 5.0 (`swift-tools-version:5.0`) and 5.1 (`swift-tools-version:5.1`):

```swift
.target(
  name: ...,
  dependencies: ["GRPC"]
)
```

##### Xcode

From Xcode 11 it is possible to [add Swift Package dependencies to Xcode
projects][xcode-spm] and link targets to products of those packages; this is the
easiest way to integrate gRPC Swift with an existing `xcodeproj`.

##### Manual Integration

Alternatively, gRPC Swift can be manually integrated into a project:

1. Build an Xcode project: `swift package generate-xcodeproj`,
1. Add the generated project to your own project, and
1. Add a build dependency on `GRPC`.

#### CocoaPods

CocoaPods support will be added in v1.0.

### Getting the `protoc` Plugins

Binary releases of `protoc`, the Protocol Buffer Compiler, are available on
[GitHub][protobuf-releases].

To build the plugins, run `make plugins` in the main directory. This uses the
Swift Package Manager to build both of the necessary plugins:
`protoc-gen-swift`, which generates Protocol Buffer support code and
`protoc-gen-grpc-swift`, which generates gRPC interface code.

To install these plugins, just copy the two executables (`protoc-gen-swift` and
`protoc-gen-grpc-swift`) that show up in the main directory into a directory
that is part of your `PATH` environment variable. Alternatively the full path to
the plugins can be specified when using `protoc`.

## Using gRPC Swift

gRPC Swift has a number of tutorials and examples available:

- A [quick start guide][docs-quickstart] for creating and running your first
  gRPC service.
- A [basic tutorial][docs-tutorial] covering the creation and implementation of
  a gRPC service using all four call types as well as the code required to setup
  and run a server and make calls to it using a generated client.

The `docs` directory contains other documenation, including:

- Options for the `protoc` plugin in [`docs/plugin.md`][docs-plugin]
- How to configure TLS in [`docs/tls.md`][docs-tls]
- Support for Apple Platforms and NIO Transport Services in
  [`docs/apple-platforms.md`][docs-apple]

## License

gRPC Swift is released under the same license as [gRPC][grpc], repeated in
[LICENSE](LICENSE).

## Contributing

Please get involved! See our [guidelines for contributing](CONTRIBUTING.md).

[docs-apple]: ./docs/apple-platforms.md
[docs-plugin]: ./docs/plugin.md
[docs-quickstart]: ./docs/quick-start.md
[docs-tls]: ./docs/tls.md
[docs-tutorial]: ./docs/basic-tutorial.md
[grpc]: https://github.com/grpc/grpc
[protobuf-releases]: https://github.com/protocolbuffers/protobuf/releases
[swift-nio-platforms]: https://github.com/apple/swift-nio#supported-platforms
[swift-nio]: https://github.com/apple/swift-nio
[swift-protobuf]: https://github.com/apple/swift-protobuf
[xcode-spm]: https://help.apple.com/xcode/mac/current/#/devb83d64851
