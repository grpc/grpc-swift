# ``GRPCCore``

A gRPC library for Swift written natively in Swift.

> 🚧 This module is part of gRPC Swift v2 which is under active development and in the pre-release
> stage.

## Package structure

gRPC Swift is made up of a number of modules, each of which is documented separately. However this
module – ``GRPCCore`` – includes higher level documentation such as tutorials. The following list
contains products of this package:

- ``GRPCCore`` contains core types and abstractions and is the 'base' module for the project.
- `GRPCInProcessTransport` contains an implementation of an in-process transport.
- `GRPCHTTP2TransportNIOPosix` provides client and server implementations of HTTP/2 transports built
  on top of SwiftNIO's POSIX Sockets abstractions.
- `GRPCHTTP2TransportNIOTransportServices` provides client and server implementations of HTTP/2
  transports built on top of SwiftNIO's Network.framework abstraction, `NIOTransportServices`.
- `GRPCProtobuf` provides serialization and deserialization components for `SwiftProtobuf`.

## Topics

### Getting involved

Resources for developers working on gRPC Swift:

- <doc:Benchmarks>
