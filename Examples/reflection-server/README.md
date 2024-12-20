# Reflection Server

This example demonstrates the gRPC Reflection service which is described in more
detail in the [gRPC documentation](https://github.com/grpc/grpc/blob/6fa8043bf9befb070b846993b59a3348248e6566/doc/server-reflection.md).

## Overview

A "reflection-server" command line tool that uses the reflection service implementation
from [grpc/grpc-swift-extras](https://github.com/grpc/grpc-swift-extras) and the
Echo service (see the 'echo' example).

The reflection service requires you to initialize it with a set of Protobuf file
descriptors for the services you're offering. You can use `protoc` to create a
descriptor set including dependencies and source information for each service.

The following command will generate a descriptor set at `path/to/output.pb` from
the `path/to/input.proto` file with source information and any imports used in
`input.proto`:

```console
protoc --descriptor_set_out=path/to/output.pb path/to/input.proto \
  --include_source_info \
  --include_imports
```

## Usage

Build and run the server using the CLI:

```console
$ swift run reflection-server
Reflection server listening on [ipv4]127.0.0.1:31415
```

You can use `grpcurl` to query the reflection service. If you don't already have
it installed follow the instructions in the `grpcurl` project's
[README](https://github.com/fullstorydev/grpcurl).

You can list all services with:

```console
$ grpcurl -plaintext 127.0.0.1:31415 list
echo.Echo
```

And describe the 'Get' method in the 'echo.Echo' service:

```console
$ grpcurl -plaintext 127.0.0.1:31415 describe echo.Echo.Get
echo.Echo.Get is a method:
// Immediately returns an echo of a request.
rpc Get ( .echo.EchoRequest ) returns ( .echo.EchoResponse );
```

You can also call the 'echo.Echo.Get' method:
```console
$ grpcurl -plaintext -d '{ "text": "Hello" }' 127.0.0.1:31415 echo.Echo.Get
{
  "text": "Hello"
}
```
