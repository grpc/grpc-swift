# Route Guide - A sample gRPC Application

This directory contains the source and generated code for the gRPC "Route Guide"
example.

The tutorial relating to this example can be found in
[grpc-swift/docs/basic-tutorial.md][basic-tutorial].

## Running

To start the server, from the root of this package run:

```sh
$ swift run RouteGuideServer
```

From another terminal, run the client:

```sh
$ swift run RouteGuideClient
```

## Regenerating client and server code

For simplicity, a shell script ([grpc-swift/Protos/generate.sh][run-protoc]) is provided
to generate client and server code:

```sh
$ Protos/generate.sh
```

[basic-tutorial]: ../../../docs/basic-tutorial.md
[run-protoc]: ../../../Protos/generate.sh
