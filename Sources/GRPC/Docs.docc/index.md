# ``GRPC``

gRPC for Swift.

grpc-swift is a Swift package that contains a gRPC Swift API and code generator.

It is intended for use with Apple's [SwiftProtobuf][swift-protobuf] support for
Protocol Buffers. Both projects contain code generation plugins for `protoc`,
Google's Protocol Buffer compiler, and both contain libraries of supporting code
that is needed to build and run the generated code.

APIs and generated code is provided for both gRPC clients and servers, and can
be built either with Xcode or the Swift Package Manager. Support is provided for
all four gRPC API styles (Unary, Server Streaming, Client Streaming, and
Bidirectional Streaming) and connections can be made either over secure (TLS) or
insecure channels.

## Supported Platforms

gRPC Swift's platform support is identical to the [platform support of Swift
NIO][swift-nio-platforms].

The earliest supported version of Swift for gRPC Swift releases are as follows:

gRPC Swift Version | Earliest Swift Version
-------------------|-----------------------
`1.0.0 ..< 1.8.0`  | 5.2
`1.8.0 ..< 1.11.0` | 5.4
`1.11.0..< 1.16.0`.| 5.5
`1.16.0..< 1.20.0` | 5.6
`1.20.0..< 1.22.0` | 5.7
`1.22.0...`        | 5.8

Versions of clients and services which are use Swift's Concurrency support
are available from gRPC Swift 1.8.0 and require Swift 5.6 and newer.

## Getting gRPC Swift

There are two parts to gRPC Swift: the gRPC library and an API code generator.

### Getting the gRPC library

The Swift Package Manager is the preferred way to get gRPC Swift. Simply add the
package dependency to your `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.15.0")
]
```

...and depend on `"GRPC"` in the necessary targets:

```swift
.target(
  name: ...,
  dependencies: [.product(name: "GRPC", package: "grpc-swift")]
]
```

### Getting the protoc Plugins

Binary releases of `protoc`, the Protocol Buffer Compiler, are available on
[GitHub][protobuf-releases].

To build the plugins, run the following in the main directory:

```sh
$ swift build --product protoc-gen-swift
$ swift build --product protoc-gen-grpc-swift
```

This uses the Swift Package Manager to build both of the necessary plugins:
`protoc-gen-swift`, which generates Protocol Buffer support code and
`protoc-gen-grpc-swift`, which generates gRPC interface code.

To install these plugins, just copy the two executables (`protoc-gen-swift` and
`protoc-gen-grpc-swift`) that show up in the main directory into a directory
that is part of your `PATH` environment variable. Alternatively the full path to
the plugins can be specified when using `protoc`.

#### Homebrew

The plugins are available from [homebrew](https://brew.sh) and can be installed with:
```bash
    $ brew install swift-protobuf grpc-swift
```

## Examples

gRPC Swift has a number of tutorials and examples available. They are split
across two directories:

- [`/Sources/Examples`][examples-in-source] contains examples which do not
  require additional dependencies and may be built using the Swift Package
  Manager.
- [`/Examples`][examples-out-of-source] contains examples which rely on
  external dependencies or may not be built by the Swift Package Manager (such
  as an iOS app).

Some of the examples are accompanied by tutorials, including:
- A [quick start guide][docs-quickstart] for creating and running your first
  gRPC service.
- A [basic tutorial][docs-tutorial] covering the creation and implementation of
  a gRPC service using all four call types as well as the code required to setup
  and run a server and make calls to it using a generated client.
- An [interceptors][docs-interceptors-tutorial] tutorial covering how to create
  and use interceptors with gRPC Swift.

## Additional documentation

- Options for the `protoc` plugin in [`docs/plugin.md`][docs-plugin]
- How to configure TLS in [`docs/tls.md`][docs-tls]
- How to configure keepalive in [`docs/keepalive.md`][docs-keepalive]
- Support for Apple Platforms and NIO Transport Services in
  [`docs/apple-platforms.md`][docs-apple]

[docs-apple]: https://github.com/grpc/grpc-swift/tree/main/docs/apple-platforms.md
[docs-plugin]: https://github.com/grpc/grpc-swift/tree/main/docs/plugin.md
[docs-quickstart]: https://github.com/grpc/grpc-swift/tree/main/docs/quick-start.md
[docs-tls]: https://github.com/grpc/grpc-swift/tree/main/docs/tls.md
[docs-keepalive]: https://github.com/grpc/grpc-swift/tree/main/docs/keepalive.md
[docs-tutorial]: https://github.com/grpc/grpc-swift/tree/main/docs/basic-tutorial.md
[docs-interceptors-tutorial]: https://github.com/grpc/grpc-swift/tree/main/docs/interceptors-tutorial.md
[grpc]: https://github.com/grpc/grpc
[protobuf-releases]: https://github.com/protocolbuffers/protobuf/releases
[swift-nio-platforms]: https://github.com/apple/swift-nio#supported-platforms
[swift-nio]: https://github.com/apple/swift-nio
[swift-protobuf]: https://github.com/apple/swift-protobuf
[xcode-spm]: https://help.apple.com/xcode/mac/current/#/devb83d64851
[branch-new]: https://github.com/grpc/grpc-swift/tree/main
[branch-old]: https://github.com/grpc/grpc-swift/tree/cgrpc
[examples-out-of-source]: https://github.com/grpc/grpc-swift/tree/main/Examples
[examples-in-source]: https://github.com/grpc/grpc-swift/tree/main/Sources/Examples
