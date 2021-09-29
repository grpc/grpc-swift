# Echo, a gRPC Sample App

This directory contains a simple echo server that demonstrates all four gRPC API
styles (Unary, Server Streaming, Client Streaming, and Bidirectional Streaming)
using the gRPC Swift.

There are four subdirectories:
* `Model/` containing the service and model definitions and generated code,
* `Implementation/` containing the server implementation of the generated model,
* `Runtime/` containing a CLI for the server and client using the NIO-based APIs.
* `AsyncAwaitRuntime/` containing a CLI for the server and client using the
    async-await–based APIs.

### CLI implementation

The SwiftPM targets for the NIO-based CLI and the async-await–based CLI are
`Echo` and `AsyncAwaitEcho` respectively.

The below examples make use the former, with commands of the form:

```sh
swift run Echo ...
```

To use the CLI using the async-await APIs, replace these commands with:

```sh
swift run AsyncAwaitEcho ...
```

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
