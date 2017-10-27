[![Build Status](https://travis-ci.org/grpc/grpc-swift.svg?branch=master)](https://travis-ci.org/grpc/grpc-swift)

# Swift gRPC 

This repository contains an experimental Swift gRPC API
and code generator.

It is intended for use with Apple's 
[swift-protobuf](https://github.com/apple/swift-protobuf)
support for Protocol Buffers. Both projects contain
code generation plugins for `protoc`, Google's 
Protocol Buffer compiler, and both contain libraries
of supporting code that is needed to build and run
the generated code.

APIs and generated code is provided for both gRPC clients
and servers, and can be built either with Xcode or the Swift
Package Manager. Support is provided for all four gRPC
API styles (Unary, Server Streaming, Client Streaming, 
and Bidirectional Streaming) and connections can be made
either over secure (TLS) or insecure channels.

The [Echo](Examples/Echo) example provides a comprehensive
demonstration of currently-supported features.

Swift Package Manager builds may also be made on Linux 
systems. Please see [DOCKER.md](DOCKER.md) and 
[LINUX.md](LINUX.md) for details.

## gRPC dependencies are vendored

Swift gRPC includes vendored copies of the gRPC core
library and **BoringSSL**, an OpenSSL fork that is used by
the gRPC Core. These are built automatically in Swift Package
Manager builds.

## Usage

The recommended way to use Swift gRPC is to first define an API using the
[Protocol Buffer](https://developers.google.com/protocol-buffers/)
language and then use the
[Protocol Buffer Compiler](https://github.com/google/protobuf)
and the [Swift Protobuf](https://github.com/apple/swift-protobuf)
and [gRPC-Swift](https://github.com/grpc/grpc-swift) plugins to
generate the necessary support code.

### Getting the dependencies

Binary releases of `protoc`, the Protocol Buffer Compiler, are
available on [GitHub](https://github.com/google/protobuf/releases).

To build the plugins, run `make` in the [Plugin](Plugin) directory.
This uses the Swift Package Manager to build both of the necessary
plugins: `protoc-gen-swift`, which generates Protocol Buffer support code
and `protoc-gen-swiftgrpc`, which generates gRPC interface code.

### Using the plugins

To use the plugins, `protoc` and both plugins should be in your
search path. Invoke them with commands like the following:

    protoc <your proto files> \
        --swift_out=. \
        --swiftgrpc_out=.

By convention the `--swift_out` option invokes the `protoc-gen-swift`
plugin and `--swiftgrpc_out` invokes `protoc-gen-swiftgrpc`.

### Building your project

Most `grpc-swift` development is done with the Swift Package Manager.
For usage in Xcode projects, we rely on the `swift package generate-xcodeproj`
command to generate an Xcode project for the `grpc-swift` core libraries.

The top-level Makefile uses the Swift Package Manager to
generate an Xcode project for the SwiftGRPC package:

    $ make

This will create `SwiftGRPC.xcodeproj`, which you should
add to your project, along with setting build dependencies
on **BoringSSL**, **CgRPC**, and **gRPC**. Due to present
limitations in Package Manager configuration, the libz
dependency is not included in the generated Xcode project. If
you get build errors about missing symbols such as
`_deflate`, `_deflateEnd`, etc., you can fix them by adding
`libz.tbd` to the **Link Binary With Libraries** build step
of the **CgRPC** target.

Please also note that your project will need to include the
**SwiftProtobuf.xcodeproj** from
[Swift Protobuf](https://github.com/apple/swift-protobuf) and
the source files that you generated with `protoc` and the plugins.

Please see [Echo](Examples/Echo) for a working Xcode-based
example and file issues if you find any problems.

### Low-level gRPC

While the recommended way to use gRPC is with Protocol Buffers
and generated code, at its core gRPC is a powerful HTTP/2-based
communication system that can support arbitrary payloads. As such,
each gRPC library includes low-level interfaces that can be used
to directly build API clients and servers with no generated code.
For an example of this in Swift, please see the
[Simple](Examples/Simple) example.

## Having build problems?

grpc-swift depends on Swift, Xcode, and swift-proto. We are currently
testing with the following versions:

- Xcode 9 
- Swift 4 (swiftlang-900.0.43 clang-900.0.22.8)
- swift-protobuf 0.9.904 

## License

grpc-swift is released under the same license as 
[gRPC](https://github.com/grpc/grpc), repeated in
[LICENSE](LICENSE). 

## Contributing

Please get involved! See our [guidelines for contributing](CONTRIBUTING.md).
