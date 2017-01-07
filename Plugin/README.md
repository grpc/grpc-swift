# Swift gRPC Plugin

This directory contains the Swift gRPC plugin for `protoc`,
the Protocol Buffer Compiler.

It is built with the Swift Package Manager and the included
Makefile. The resulting binary is named `protoc-gen-swiftgrpc`
and can be called from `protoc` by adding the `--swiftgrpc_out`
command-line option. For example, here's an invocation from
the Makefile:

	protoc ../Examples/Echo/echo.proto --proto_path=../Examples/Echo --swiftgrpc_out=. 

The plugin uses template files in the [templates](templates) 
directory. This directory currently must be in the same location 
where the compiler is run.

