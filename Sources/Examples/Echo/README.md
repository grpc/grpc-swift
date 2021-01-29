# Echo, a gRPC Sample App

This directory contains a simple echo server that demonstrates all four gRPC API
styles (Unary, Server Streaming, Client Streaming, and Bidirectional Streaming)
using the gRPC Swift.

There are three subdirectories:
* `Model` containing the service and model definitions and generated code,
* `Implementation` containing the server implementation of the generated model,
* `Runtime` containing a CLI for the server and client.

### Server

To start the server run:

```sh
swift run Echo server
```

By default the server listens on port 1234. The port may also be specified by
passing the `--port` option. Other options may be found by running:

```sh
swift run Echo server --help
```

### Client

To invoke the 'get' (unary) RPC with the message "Hello, World!" against the
server:

```sh
swift run Echo client "Hello, World!"
```

Different RPC types can be called using the `--rpc` flag (which defaults to
'get'):
- 'get': a unary RPC; one request and one response
- 'collect': a client streaming RPC; multiple requests and one response
- 'expand': a server streaming RPC; one request and multiple responses
- 'update': a bidirectional streaming RPC; multiple requests and multiple
  responses

Additional options may be found by running:

```sh
swift run Echo client --help
```
