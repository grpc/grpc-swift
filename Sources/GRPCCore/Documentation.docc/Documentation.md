# ``GRPCCore``

A gRPC library for Swift written natively in Swift.

## Overview

### Package structure

gRPC Swift is distributed across multiple Swift packages. These are:

- `grpc-swift` (this package) containing core gRPC abstractions and an in-process transport.
  - GitHub repository: [`grpc/grpc-swift`](https://github.com/grpc/grpc-swift)
  - Documentation: hosted on the [Swift Package
    Index](https://swiftpackageindex.com/grpc/grpc-swift/documentation)
- `grpc-swift-nio-transport` contains high-performance HTTP/2 transports built on top
    of [SwiftNIO](https://github.com/apple/swift-nio).
  - GitHub repository: [`grpc/grpc-swift-nio-transport`](https://github.com/grpc/grpc-swift-nio-transport)
  - Documentation: hosted on the [Swift Package
    Index](https://swiftpackageindex.com/grpc/grpc-swift-nio-transport/documentation)
- `grpc-swift-protobuf` contains runtime serialization components to interoperate with
    [SwiftProtobuf](https://github.com/apple/swift-protobuf) as well as a plugin for the Protocol
    Buffers compiler, `protoc`.
  - GitHub repository: [`grpc/grpc-swift-protobuf`](https://github.com/grpc/grpc-swift-protobuf)
  - Documentation: hosted on the [Swift Package
    Index](https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation)
- `grpc-swift-extras` contains optional runtime components and integrations with other packages.
  - GitHub repository: [`grpc/grpc-swift-extras`](https://github.com/grpc/grpc-swift-extras)
  - Documentation: hosted on the [Swift Package
    Index](https://swiftpackageindex.com/grpc/grpc-swift-extras/documentation)

This package, and this module (``GRPCCore``) in particular, include higher level documentation such
as tutorials.

### Modules in this package

- ``GRPCCore`` (this module) contains core abstractions, currency types and runtime components
  for gRPC Swift.
- `GRPCInProcessTransport` contains an in-process implementation of the ``ClientTransport`` and
  ``ServerTransport`` protocols.
- `GRPCodeGen` contains components for building a code generator.

## Topics

### Tutorials

- <doc:Hello-World>
- <doc:Route-Guide>

### Essentials

- <doc:Generating-stubs>
- <doc:Error-handling>

### Project Information

- <doc:Compatibility>
- <doc:Public-API>
- <doc:Migration-guide>

### Getting involved

Resources for developers working on gRPC Swift:

- <doc:Design>
- <doc:Benchmarks>

### Client and Server

- ``GRPCClient``
- ``GRPCServer``
- ``withGRPCClient(transport:interceptors:isolation:handleClient:)``
- ``withGRPCClient(transport:interceptorPipeline:isolation:handleClient:)``
- ``withGRPCServer(transport:services:interceptors:isolation:handleServer:)``
- ``withGRPCServer(transport:services:interceptorPipeline:isolation:handleServer:)``

### Request and response types

- ``ClientRequest``
- ``StreamingClientRequest``
- ``ClientResponse``
- ``StreamingClientResponse``
- ``ServerRequest``
- ``StreamingServerRequest``
- ``ServerResponse``
- ``StreamingServerResponse``

### Service definition and routing

- ``RegistrableRPCService``
- ``RPCRouter``

### Interceptors

- ``ClientInterceptor``
- ``ServerInterceptor``
- ``ClientContext``
- ``ServerContext``
- ``ConditionalInterceptor``

### RPC descriptors

- ``MethodDescriptor``
- ``ServiceDescriptor``

### Service config

- ``ServiceConfig``
- ``MethodConfig``
- ``HedgingPolicy``
- ``RetryPolicy``
- ``RPCExecutionPolicy``

### Serialization

- ``MessageSerializer``
- ``MessageDeserializer``
- ``CompressionAlgorithm``
- ``CompressionAlgorithmSet``

### Transport protocols and supporting types

- ``ClientTransport``
- ``ServerTransport``
- ``RPCRequestPart``
- ``RPCResponsePart``
- ``Status``
- ``Metadata``
- ``RetryThrottle``
- ``RPCStream``
- ``RPCWriterProtocol``
- ``ClosableRPCWriterProtocol``
- ``RPCWriter``
- ``RPCAsyncSequence``

### Cancellation

- ``withServerContextRPCCancellationHandle(_:)``
- ``withRPCCancellationHandler(operation:onCancelRPC:)``

### Errors

- ``RPCError``
- ``RPCErrorConvertible``
- ``RuntimeError``
