# Reflection service

This tutorial goes through the steps of adding Reflection service to a 
server, running it and testing it using gRPCurl. 

 The server used in this example is implemented at 
 [Sources/Examples/ReflectionService/ReflectionServer.swift][reflectionservice-server]
 and it supports the "Greeter", "Echo", and "Reflection" services. 


## Overview

The Reflection service provides information about the public RPCs served by a server. 
It is specific to services defined using the Protocol Buffers IDL.
By calling the Reflection service, clients can construct and send requests to services
without needing to generate code and types for them. 

You can also use CLI clients such as [gRPCurl][grpcurl-setup] and the [gRPC command line tool][grpc-cli] to: 
- list services,
- describe services and their methods,
- describe symbols,
- describe extensions,
- construct and invoke RPCs.

gRPC Swift supports both [v1][v1] and [v1alpha][v1alpha] of the reflection service.

## Adding the Reflection service to a server

You can use the Reflection service by adding it in the providers when constructing your server.

To initialise the Reflection service we will use 
``GRPCReflectionService/ReflectionService/init(reflectionDataFilePaths:version:)``.
It receives the paths to the files containing the reflection data of the proto files 
describing the services of the server that we want to be discoverable through reflection
and the version of the reflection service.


### Generating the reflection data

The server from this example uses the `GreeterProvider` and the `EchoProvider`,
besides the `ReflectionService`.

The associated proto files are located at `Sources/Examples/HelloWorld/Model/helloworld.proto`, and 
`Sources/Examples/Echo/Model/echo.proto` respectively.

In order to generate the reflection data for the `helloworld.proto`, you can run the following command:

```sh
$ protoc Sources/Examples/HelloWorld/Model/helloworld.proto \
    --proto_path=Sources/Examples/HelloWorld/Model \
    --grpc-swift_opt=Client=false,Server=false,ReflectionData=true \
    --grpc-swift_out=Sources/Examples/ReflectionService/Generated
```

Let's break the command down:
- The first argument passed to `protoc` is the path 
  to the `.proto` file to generate reflection data 
  for: [`Sources/Examples/HelloWorld/Model/helloworld.proto`][helloworld-proto].
- The `proto_path` flag is the path to search for imports: `Sources/Examples/HelloWorld/Model`.
- To generate only the reflection data set: `Client=false,Server=false,ReflectionData=true`.
- The `grpc-swift_out` flag is used to set the path of the directory
  where the generated file will be located: `Sources/Examples/ReflectionService/Generated`.

This command assumes that the `protoc-gen-grpc-swift` plugin is part of the $PATH environment variable.
You can learn how to get the plugin from this section of the `grpc-swift` README: 
https://github.com/grpc/grpc-swift#getting-the-protoc-plugins.

The command for generating the reflection data for the `Echo` service is similar.

### Instantiating the Reflection service 

To instantiate the `ReflectionService` you need to pass the file paths of
the generated reflection data and the version to use, in our case `.v1`.

Depending on the version of [gRPCurl][grpcurl] you are using you might need to use the v1alpha proto instead.
Beginning with [gRPCurl v1.8.8][grpcurl-v188] it uses the [v1][v1] reflection. Earlier versions use [v1alpha][v1alpha]
reflection.

```swift
// Constructing the absolute paths to the files containing the reflection data
// using their relative paths to #filePath.
let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let helloworldPath: String
let echoPath: String
#if os(Linux)
helloworldPath = url.appendingPathComponent("Generated/helloworld.grpc.reflection.txt").path
echoPath = url.appendingPathComponent("Generated/echo.grpc.reflection.txt").path
#else
helloworldPath = url.appendingPathComponent("Generated/helloworld.grpc.reflection.txt").path()
echoPath = url.appendingPathComponent("Generated/echo.grpc.reflection.txt").path()
#endif

let reflectionService = try ReflectionService(
  reflectionDataFilePaths: [helloworldPath, echoPath],
  version: .v1
)
```

### Running the server

In our example the server isn't configured with TLS and listens on localhost port 1234.
The following code configures and starts the server:

```swift
let server = try await Server.insecure(group: group)
  .withServiceProviders([reflectionService, GreeterProvider(), EchoProvider()])
  .bind(host: "localhost", port: self.port)
  .get()

```

To run the server, from the root of the package run:

```sh
$ swift run ReflectionServer
```

## Calling the Reflection service with gRPCurl

Please follow the instructions from the [gRPCurl README][grpcurl-setup] to set up gRPCurl.

From a different terminal than the one used for running the server, we will call gRPCurl commands,
following the format: `grpcurl [flags] [address] [list|describe] [symbol]`.

We use the `-plaintext` flag, because the server isn't configured with TLS, and 
the address is set to `localhost:1234`.


To see the available services use `list`:

```sh
$ grpcurl -plaintext localhost:1234 list
echo.Echo
helloworld.Greeter
```

You can also see what methods are available for a service:

```sh
$ grpcurl -plaintext localhost:1234 list echo.Echo
echo.Echo.Collect
echo.Echo.Expand
echo.Echo.Get
echo.Echo.Update
```

You can also get descriptions of objects like services, methods, and messages. The following
command fetches a description of the Echo service:

```sh
$ grpcurl -plaintext localhost:1234 describe echo.Echo
echo.Echo is a service:
service Echo {
  // Collects a stream of messages and returns them concatenated when the caller closes.
  rpc Collect ( stream .echo.EchoRequest ) returns ( .echo.EchoResponse );
  // Splits a request into words and returns each word in a stream of messages.
  rpc Expand ( .echo.EchoRequest ) returns ( stream .echo.EchoResponse );
  // Immediately returns an echo of a request.
  rpc Get ( .echo.EchoRequest ) returns ( .echo.EchoResponse );
  // Streams back messages as they are received in an input stream.
  rpc Update ( stream .echo.EchoRequest ) returns ( stream .echo.EchoResponse );
}
```

You can also send requests to the services with gRPCurl:

```sh
$ grpcurl -d '{ "text": "test" }' -plaintext localhost:1234 echo.Echo.Get
{
  "text": "Swift echo get: test"
}
```

Note that when specifying a service, a method or a symbol, we have to use the fully qualified names:
- service: \<package\>.\<service\>
- method: \<package\>.\<service\>.\<method\>
- type: \<package\>.\<type\>

[grpcurl-setup]: https://github.com/fullstorydev/grpcurl#grpcurl
[grpcurl]: https://github.com/fullstorydev/grpcurl
[grpc-cli]: https://github.com/grpc/grpc/blob/master/doc/command_line_tool.md
[v1]: GRPCReflectionService/v1/reflection-v1.proto
[v1alpha]: ../v1Alpha/reflection-v1alpha.proto
[reflectionservice-server]: ../ReflectionService/ReflectionServer.swift
[helloworld-proto]: ../Examples/HelloWorld/Model/helloworld.proto
[echo-proto]: ../../../Examples/Echo/Model/echo.proto
[grpcurl-v188]: https://github.com/fullstorydev/grpcurl/releases/tag/v1.8.8
