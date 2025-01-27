# Echo-Metadata

This example demonstrates how to interact with `Metadata` on RPCs: how to set and read it on unary 
and streaming requests, as well as how to set and read both initial and trailing metadata on unary 
and streaming responses. This is done using a simple 'echo' server and client and the Swift NIO 
based HTTP/2 transport.

## Overview

An `echo-metadata` command line tool that uses generated stubs for an 'echo' service
which allows you to start a server and to make requests against it. The client will automatically
run a unary request followed by a bidirectional streaming request. In both cases, no message will
be sent as part of the request: only the metadata provided as arguments to the executable will be
included.
The server will then echo back all metadata key-value pairs that begin with "echo-". No message 
will be included in the responses, and the echoed values will be included in both the initial and
the trailing metadata.

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

Use the CLI to run the client and make a unary request followed by a bidirectional streaming one:

```console
$ PROTOC_PATH=$(which protoc) swift run echo-metadata echo --metadata "echo-key=value" --metadata "another-key=value"
unary → [("echo-key", value)]
unary ← Initial metadata: [("echo-key", value)]
unary ← Trailing metadata: [("echo-key", value)]
bidirectional → [("echo-key", value)]
bidirectional ← Initial metadata: [("echo-key", value)]
bidirectional ← Trailing metadata: [("echo-key", value)]
```

Get help with the CLI by running:

```console
$ PROTOC_PATH=$(which protoc) swift run echo-metadata --help
```

[0]: https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation/grpcprotobuf/installing-protoc
[1]: https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation/grpcprotobuf/generating-stubs
