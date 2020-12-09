# Hello World, a quick-start gRPC Example

This directory contains a 'Hello World' gRPC example, a single service with just
one RPC for saying hello. The quick-start tutorial which accompanies this
example lives in `docs/` directory of this project.

## Running

### Server

To start the server run:

```sh
swift run HelloWorldServer
```

Note the port the server is listening on.

### Client

To send a message to the server run the following, replacing `<PORT>` with the
port the server is listening on:

```sh
swift run HelloWorldClient <PORT>
```

You may also greet a particular person (or dog). For example, to greet
[PanCakes](https://grpc.io/blog/hello-pancakes/) on a server listening on port
1234 run:

```sh
swift run HelloWorldClient 1234 "PanCakes"
```
