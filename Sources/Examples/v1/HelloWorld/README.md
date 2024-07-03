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

### Client

To send a message to the server run the following:

```sh
swift run HelloWorldClient
```

You may also greet a particular person (or dog). For example, to greet
[PanCakes](https://grpc.io/blog/hello-pancakes/) run:

```sh
swift run HelloWorldClient PanCakes
```
