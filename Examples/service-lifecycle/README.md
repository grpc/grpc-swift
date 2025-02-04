# Service Lifecycle

This example demonstrates gRPC Swift's integration with Swift Service Lifecycle
which is provided by the gRPC Swift Extras package.

## Overview

A "service-lifecycle" command line tool that uses generated stubs for a
'greeter' service starts an in-process client and server orchestrated using
Swift Service Lifecycle. The client makes requests against the server which
periodically changes its greeting.

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
$ PROTOC_PATH=$(which protoc) swift run service-lifecycle
Здравствуйте, request-1!
नमस्ते, request-2!
你好, request-3!
French, request-4!
Olá, request-5!
Hola, request-6!
Hello, request-7!
Hello, request-8!
नमस्ते, request-9!
Hello, request-10!
```

[0]: https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation/grpcprotobuf/installing-protoc
[1]: https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation/grpcprotobuf/generating-stubs
