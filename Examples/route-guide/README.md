# Route Guide

This example demonstrates all four RPC types using a 'Route Guide' service and
client.

## Overview

A "route-guide" command line tool that uses generated stubs for a 'Route Guide'
service allows you to start a server and to make requests against it for
each of the four RPC types.

The tool uses the [SwiftNIO](https://github.com/grpc/grpc-swift-nio-transport)
HTTP/2 transport.

This example has an accompanying tutorial hosted on the [Swift Package
Index](https://swiftpackageindex.com/grpc/grpc-swift/main/tutorials/grpccore/route-guide).

## Usage

Build and run the server using the CLI:

```console
$ swift run route-guide serve
server listening on [ipv4]127.0.0.1:31415
```

Use the CLI to interrogate the different RPCs you can call:

```console
$ swift run route-guide --help
USAGE: route-guide <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  serve                   Starts a route-guide server.
  get-feature             Gets a feature at a given location.
  list-features           List all features within a bounding rectangle.
  record-route            Records a route by visiting N randomly selected points and prints a summary of it.
  route-chat              Visits a few points and records a note at each, and prints all notes previously recorded at each point.

  See 'route-guide help <subcommand>' for detailed help.
```
