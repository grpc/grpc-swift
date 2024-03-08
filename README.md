[![CI](https://img.shields.io/github/workflow/status/grpc/grpc-swift/CI?event=push)](https://github.com/grpc/grpc-swift/actions/workflows/ci.yaml)
[![Latest Version](https://img.shields.io/github/v/release/grpc/grpc-swift?include_prereleases&sort=semver)](https://img.shields.io/github/v/release/grpc/grpc-swift?include_prereleases&sort=semver)
[![sswg:graduated|104x20](https://img.shields.io/badge/sswg-graduated-green.svg)](https://github.com/swift-server/sswg/blob/main/process/incubation.md#graduated-level)

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

## Versions

gRPC Swift has recently been rewritten on top of [SwiftNIO][swift-nio] as
opposed to the core library provided by the [gRPC project][grpc].

Version | Implementation | Branch                 | `protoc` Plugin         | Support
--------|----------------|------------------------|-------------------------|-----------------------------------------
1.x     | SwiftNIO       | [`main`][branch-new]   | `protoc-gen-grpc-swift` | Actively developed and supported
0.x     | gRPC C library | [`cgrpc`][branch-old]  | `protoc-gen-swiftgrpc`  | No longer developed; security fixes only

The remainder of this README refers to the 1.x version of gRPC Swift.


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

#### Swift Package Manager

The Swift Package Manager is the preferred way to get gRPC Swift. Simply add the
package dependency to your `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.21.0")
]
```

...and depend on `"GRPC"` in the necessary targets:

```swift
.target(
  name: ...,
  dependencies: [.product(name: "GRPC", package: "grpc-swift")]
]
```

### Getting the `protoc` Plugins

Binary releases of `protoc`, the Protocol Buffer Compiler, are available on
[GitHub][protobuf-releases].

To build the plugins, run:
- `swift build -c release --product protoc-gen-swift` to build the `protoc`
  plugin which generates Protocol Buffer support code, and
- `swift build -c release --product protoc-gen-grpc-swift` to build the `protoc` plugin
  which generates gRPC interface code.

To install these plugins, just copy the two executables (`protoc-gen-swift` and
`protoc-gen-grpc-swift`) from the build directory (`.build/release`) into a directory
that is part of your `PATH` environment variable. Alternatively the full path to
the plugins can be specified when using `protoc`.

### Using the Swift Package Manager plugin

You can also use the Swift Package Manager build plugin to generate messages and
gRPC code at build time rather than using `protoc` to generate them ahead of
time. Using this method Swift Package Manager takes care of building
`protoc-gen-swift` and `protoc-gen-grpc-swift` for you.

One important distinction between using the Swift Package Manager build plugin
and generating the code ahead of time is that the build plugin has an implicit
dependency on `protoc`. It's therefore unsuitable for _libraries_ as they can't
guarantee that end users will have `protoc` available at compile time.

You can find more documentation about the Swift Package Manager build plugin in
[Using the Swift Package Manager plugin][spm-plugin-grpc].

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

## Documentation

The `docs` directory contains documentation, including:

- Options for the `protoc` plugin in [`docs/plugin.md`][docs-plugin]
- How to configure TLS in [`docs/tls.md`][docs-tls]
- How to configure keepalive in [`docs/keepalive.md`][docs-keepalive]
- Support for Apple Platforms and NIO Transport Services in
  [`docs/apple-platforms.md`][docs-apple]

## Benchmarks

Benchmarks for `grpc-swift` are in a separate Swift Package in the `Performance/Benchmarks` subfolder of this repository.
They use the [`package-benchmark`](https://github.com/ordo-one/package-benchmark) plugin.
Benchmarks depends on the [`jemalloc`](https://jemalloc.net) memory allocation library, which is used by `package-benchmark` to capture memory allocation statistics.
An installation guide can be found in the [Getting Started article](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark/gettingstarted#Installing-Prerequisites-and-Platform-Support) of `package-benchmark`.
Afterwards you can run the benchmarks from CLI by going to the `Performance/Benchmarks` subfolder (e.g. `cd Performance/Benchmarks`) and invoking:
```
swift package benchmark
```

Profiling benchmarks or building the benchmarks in release mode in Xcode with `jemalloc` is currently not supported and requires disabling `jemalloc`.
Make sure Xcode is closed and then open it from the CLI with the `BENCHMARK_DISABLE_JEMALLOC=true` environment variable set e.g.:
```
BENCHMARK_DISABLE_JEMALLOC=true xed .
```

For more information please refer to `swift package benchmark --help` or the [documentation of `package-benchmark`](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark).

## Security

Please see [SECURITY.md](SECURITY.md).

## License

gRPC Swift is released under the same license as [gRPC][grpc], repeated in
[LICENSE](LICENSE).

## Contributing

Please get involved! See our [guidelines for contributing](CONTRIBUTING.md).

[docs-apple]: ./docs/apple-platforms.md
[docs-plugin]: ./docs/plugin.md
[docs-quickstart]: ./docs/quick-start.md
[docs-tls]: ./docs/tls.md
[docs-keepalive]: ./docs/keepalive.md
[docs-tutorial]: ./docs/basic-tutorial.md
[docs-interceptors-tutorial]: ./docs/interceptors-tutorial.md
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
[spm-plugin-grpc]: https://swiftpackageindex.com/grpc/grpc-swift/main/documentation/protoc-gen-grpc-swift/spm-plugin
