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
systems. Please see [LINUX.md](LINUX.md) for details.

## Getting started

After cloning this repository, `cd third_party; RUNME.sh` to
download its dependencies. (We don't use `git submodules` so
that the repository will stay lean when it is imported with the
the Swift Package Manager.)

## Building grpc

Swift gRPC currently requires a separate build of the grpc core
library. To do this, enter the grpc directory and run 
`git submodule update --init` and then `make install`. 
If you get build errors, edit the Makefile and remove 
"-Werror" from the line that begins with "CPPFLAGS +=".

## Having build problems?

grpc-swift depends on Swift, Xcode, and swift-proto, all of which
are in flux and potential sources of breaking changes. We are currently
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
