# Hello World

This example demonstrates the canonical "Hello World" in gRPC.

## Overview

A "hello-world" command line tool that uses generated stubs for the 'Greeter'
service which allows you to start a server and to make requests against it.

The tool uses the [SwiftNIO](https://github.com/grpc/grpc-swift-nio-transport)
HTTP/2 transport.

## Usage

Build and run the server using the CLI:

```console
$ swift run hello-world serve
Greeter listening on [ipv4]127.0.0.1:31415
```

Use the CLI to send a request to the service:

```console
$ swift run hello-world greet
Hello, stranger
```

Send the name of the greetee in the request by specifying a `--name`:

```console
$ swift run hello-world greet --name "PanCakes 🐶"
Hello, PanCakes 🐶
```
