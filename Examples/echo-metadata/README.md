# Echo-Metadata

This example demonstrates how to interact with `Metadata` on RPCs: how to set and read it on unary 
and streaming requests, as well as how to set and read both initial and trailing metadata on unary 
and streaming responses. This is done using a simple 'echo' server and client and the SwiftNIO 
based HTTP/2 transport.

## Overview

An `echo-metadata` command line tool that uses generated stubs for an 'echo-metadata' service
which allows you to start a server and to make requests against it. 

You can use any of the client's subcommands (`get`, `collect`, `expand` and `update`) to send the
provided `message` as both the request's message, and as the value for the `echo-message` key in
the request's metadata.

The server will then echo back the message and the metadata's `echo-message` key-value pair sent
by the client. The request's metadata will be echoed both in the initial and the trailing metadata.

The tool uses the [SwiftNIO](https://github.com/grpc/grpc-swift-nio-transport) HTTP/2 transport.

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
$ PROTOC_PATH=$(which protoc) swift run echo-metadata serve
Echo-Metadata listening on [ipv4]127.0.0.1:1234
```

Use the CLI to run the client and make a `get` (unary) request:

```console
$ PROTOC_PATH=$(which protoc) swift run echo-metadata get --message "hello"
get → metadata: [("echo-message", "hello")]
get → message: hello
get ← initial metadata: [("echo-message", "hello")]
get ← message: hello
get ← trailing metadata: [("echo-message", "hello")]
```

Get help with the CLI by running:

```console
$ PROTOC_PATH=$(which protoc) swift run echo-metadata --help
```

[0]: https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation/grpcprotobuf/installing-protoc
[1]: https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation/grpcprotobuf/generating-stubs
