# Echo

This example demonstrates all four RPC types using a simple 'echo' service and
client and the SwiftNIO based HTTP/2 transport.

## Overview

An "echo" command line tool that uses generated stubs for an 'echo' service
which allows you to start a server and to make requests against it for each of
the four RPC types.

The tool uses the [SwiftNIO](https://github.com/grpc/grpc-swift-nio-transport)
HTTP/2 transport.

## Prerequisites

You must have the Protocol Buffers compiler (`protoc`) installed. You can find
the instructions for doing this in the [gRPC Swift Protobuf documentation][0].
The `swift` commands below are all prefixed with `PROTOC_PATH=$(which protoc)`,
this is to let the build system know where `protoc` is located so that it can
generate stubs for you. You can read more about it in the [gRPC Swift Protobuf
documentation][1].

## Usage

Build and run the server using the CLI:

```console
$ PROTOC_PATH=$(which protoc) swift run echo serve
Echo listening on [ipv4]127.0.0.1:1234
```

Use the CLI to make a unary 'Get' request against it:

```console
$ PROTOC_PATH=$(which protoc) swift run echo get --message "Hello"
get → Hello
get ← Hello
```

Use the CLI to make a bidirectional streaming 'Update' request:

```console
$ PROTOC_PATH=$(which protoc) swift run echo update --message "Hello World"
update → Hello
update → World
update ← Hello
update ← World
```

Get help with the CLI by running:

```console
$ PROTOC_PATH=$(which protoc) swift run echo --help
```

[0]: https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation/grpcprotobuf/installing-protoc
[1]: https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation/grpcprotobuf/generating-stubs
