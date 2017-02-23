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

Swift gRPC now includes vendored copies of the gRPC core 
library and **BoringSSL**, an OpenSSL fork that is used by
the gRPC Core. These are built automatically in Swift Package
Manager builds.

## Building with Xcode

The top-level Makefile uses the Swift Package Manager to generate
an Xcode project for the SwiftGRPC package. Due to present limitations
in Package Manager configuration, the libz dependency is not included 
in the generated Xcode project. If you get build errors about missing
symbols such as `_deflate`, `_deflateEnd`, etc., you can fix them by
adding `libz.tbd` to the **Link Binary With Libraries** build step of 
the **CgRPC** target.

## Having build problems?

grpc-swift depends on Swift, Xcode, and swift-proto. We are currently
testing with the following versions:

- Xcode 8.2 
- Swift 3.0.2 
- swift-proto 0.9.24 

## License

grpc-swift is released under the same license as 
[gRPC](https://github.com/grpc/grpc), repeated in
[LICENSE](LICENSE). 

## Contributing

Please get involved! See our [guidelines for contributing](CONTRIBUTING.md).
