# Echo, a gRPC Sample App

This directory contains a simple echo server that demonstrates all four gRPC API
styles (Unary, Server Streaming, Client Streaming, and Bidirectional Streaming)
using the gRPC Swift.

There are three subdirectories:
* `Model` containing the service and model definitions and generated code,
* `Implementation` containing the server implementation of the generated model,
* `Runtime` containing a CLI for the server and client.

## Running

### Server

To start the server on a free port run:

```sh
swift run Echo server 0
```

To start the server with TLS enabled on port 1234:

```sh
swift run Echo server --tls 1234
```

### Client

To invoke the 'get' (unary) RPC with the message "Hello, World!" against a
server listening on port 5678 run:

```sh
swift run Echo 5678 get "Hello, World!"
```

To invoke the 'update' (bidirectional streaming) RPC against a server with TLS
enabled listening on port 1234 run:

```sh
swift run Echo --tls 1234 update "Hello from the client!"
```

The client may also be run with an `--intercept` flag, this will print
additional information about each RPC and is covered in more detail in the
interceptors tutorial (in the `docs` directory of this project):

```sh
swift run Echo --tls --intercept 1234 get "Hello from the interceptors!"
```
