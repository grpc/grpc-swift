# Swift gRPC Plugin

This directory contains the Swift gRPC plugin for `protoc`,
the Protocol Buffer Compiler.

It is built with the Swift Package Manager and the included
Makefile. The resulting binary is named `protoc-gen-swiftgrpc`
and can be called from `protoc` by adding the `--swiftgrpc_out`
command-line option and `--plugin` option. For example, here's an
invocation from the Makefile:

		protoc ../Examples/Echo/echo.proto --proto_path=../Examples/Echo --plugin=./protoc-gen-swiftgrpc --swiftgrpc_out=.

The Swift gRPC plugin can be installed by placing the
`protoc-gen-swiftgrpc` binary into one of the directories in your
path.  Specifying `--swiftgrpc_out` to `protoc` will automatically
search the `PATH` environment variable for this binary.
