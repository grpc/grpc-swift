# Echo

This example demonstrates all four RPC types using a simple 'echo' service and
client and the Swift NIO based HTTP/2 transport.

## Overview

An "echo" command line tool that uses generated stubs for an 'echo' service
which allows you to start a server and to make requests against it for each of
the four RPC types.

The tool uses the [SwiftNIO](https://github.com/grpc/grpc-swift-nio-transport)
HTTP/2 transport.

## Usage

Build and run the server using the CLI:

```console
$ swift run echo serve
Echo listening on [ipv4]127.0.0.1:1234
```

Use the CLI to make a unary 'Get' request against it:

```console
$ swift run echo get --message "Hello"
get → Hello
get ← Hello
```

Use the CLI to make a bidirectional streaming 'Update' request:

```console
$ swift run echo update --message "Hello World"
update → Hello
update → World
update ← Hello
update ← World
```

Get help with the CLI by running:

```console
$ swift run echo --help
```
