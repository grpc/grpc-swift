# ReflectionServiceTutorial

This tutorial goes through the steps of adding Reflection Service to a Swift
Server, running it and testing it using GRPCurl. 

 The Server used in this example is implemented at 
 [Sources/Examples/ReflectionService/ReflectionServiceServer.swift][reflectionservice-server]
 and it supports the `HelloWord`, `Echo`, and `Reflection` services. 


## Reflection Service
The Reflection Service provides information about the public RPCs on a Server and,
at the moment, it is specific for Servers that use the Protobuf schema to define their RPCs. 
Calling the Reflection Service, clients can construct and send requests at runtime, without 
needing the proto files or the protoc generated code and types for this. 

The Reflection Service is used by cli clients such as [gRPCurl][grpcurl-setup] and [gRPC command line tool][grpc-cli],
to list and describe services and methods, or to describe symbols or extensions, but also
to construct and make test RPCs to the servers.

The Swift Reflection Service supports both v1 and v1alpha versions of reflection: 
- [v1]
- [v1alpha]

## Adding the Reflection Service to a Server
The Swift Reflection Service is enabled by adding it in the providers list when constructing the Server.

The Reflection Service provider has two initialisers:
- ``GRPCReflectionService/ReflectionService/init(serializedFileDescriptorProtoFilePaths:version:)``:
  Receives the paths to the files containing the base64 encoded 
  serialized file descriptor protos of the proto files describing 
  the services of the Server that we want to be discoverable through reflection
  and the version of the reflection service.
- ``GRPCReflectionService/ReflectionService/init(fileDescriptorProtos:version:)``:
  Receives as parameters the file descriptor protos of the proto files describing
  the services of the Server that we want to be discoverable 
  through reflection and the version of the reflection service.

We recommend using the first one as it is more convinient. We will use it in this example as well.
Before initialising the ReflectionService provider we need to generate the
files containing the base64 encoded serialized file descriptor protos.


### Generating the serialized file descriptor protos for the Server
 The Server from this example uses the `GreeterProvider`, `EchoProvider` and the 
 `ReflectionService` (v1 version). The associated proto files are located at 
 `Sources/Examples/HelloWorld/Model/helloworld.proto`, 
 `Sources/Examples/Echo/Model/echo.proto`, and 
 `Sources/GRPCReflectionService/v1/reflection-v1.proto` respectively.

 In order to generate the serialized file descriptor proto for the
 `helloworld.proto`, you can run the following command:

```sh
$ protoc Sources/Examples/HelloWorld/Model/helloworld.proto \
    --proto_path=Sources/Examples/HelloWorld/Model \
    --plugin=./.build/debug/protoc-gen-grpc-swift \
    --grpc-swift_opt=Client=false,Server=false,ReflectionData=true \
    --grpc-swift_out=Sources/Examples/ReflectionService/Generated
```

Let's break the command down:
 - The first argument that we are passing to `protoc` is the path 
to the proto file we want to generate the serialized file descriptor proto
for: [Sources/Examples/HelloWorld/Model/helloworld.proto][helloworld-proto].
- The `proto_path` flag is the path to search for imports: 
Sources/Examples/HelloWorld/Model.
- The plugin we are using is `./.build/debug/protoc-gen-grpc-swift`.
- The options for the `grpc-swift_opt` flag that we should set are:
`Client=false,Server=false`, because we don't want to generate code
and `ReflectionData=true` to signal that we want to generate a
file containing the serialized file descriptor proto.
- The `grpc-swift_out` flag is used to set the path of the directory
where the generated file will be located in: Sources/Examples/ReflectionService/Generated.

The commands for generating the binary files representing the serialized file descriptor 
protos for the `Echo` and `Reflection` services are similar. The path of the output
directory, the plugin and the options are the same. The path to search for imports
is the parent directory of the proto file.

The paths of the proto files are: 
- [Sources/Examples/Echo/Model/echo.proto][echo-proto]
- [Sources/GRPCReflectionService/v1/reflection-v1.proto][v1]

Depending on the version of gRPCurl you are using you might need to use the v1alpha proto instead.

 ### Instantiating the Reflection Service 

 In the Server implementation, we have to instantiate each provider.
 For instantiating the `ReflectionService` provider we have to pass in an array
 of Strings representing the paths to the binary files we have just generated,
withing the project and the version of the reflection, in our case v1.


```swift
let paths = [
  "Sources/Examples/ReflectionService/Generated/helloworld.grpc.reflection.txt", 
  "Sources/Examples/ReflectionService/Generated/echo.grpc.reflection.txt", 
  "Sources/Examples/ReflectionService/Generated/reflection.grpc.reflection.txt"
  ]

let reflectionServiceProvider = try ReflectionService(
  serializedFileDescriptorProtoFilePaths: paths, version: .v1
)
```

### Running the Server

In our example the server is not configured with TLS. The port is `1234`.
Starting the server:

```swift
let server = try await Server.insecure(group: group)
  .withServiceProviders([reflectionServiceProvider, GreeterProvider(), EchoProvider()])
  .bind(host: "localhost", port: self.port)
  .get()

```

To run the server, from the root of the package run:

```sh
$ swift run ReflectionServiceServer
```

 ## Testing the Reflection Service using GRPCurl

Please follow the instructions from the [GRPCurl README][grpcurl-setup] in order to set gRPCurl up.

From a different terminal than the one used for running the Server, we will call gRPCurl commands,
following the format:

`grpcurl [flags] [address] [list|describe] [symbol]`.

In our case we are using the `-plaintext` flag, because our server isn't configured with TLS, and 
the address is set to `localhost:1234`.

Here are some gRPCurl commands and the responses:

- **List services**
```sh
$ grpcurl -plaintext localhost:1234 list
```

**output:**
```sh
Echo
Greeter
ServerReflection
```

- **List methods of a service**
```sh
$ grpcurl -plaintext localhost:1234 list echo.Echo
```

**output:**
```sh
echo.Echo.Collect
echo.Echo.Expand
echo.Echo.Get
echo.Echo.Update
```

- **Describe a service**
```sh
$ grpcurl -plaintext localhost:1234 describe echo.Echo
```

**output:**
```
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

- **Describe a method**
```sh
$ grpcurl -plaintext localhost:1234 describe echo.Echo.Collect
```

**output:**
```
echo.Echo.Collect is a method:
// Collects a stream of messages and returns them concatenated when the caller closes.
rpc Collect ( stream .echo.EchoRequest ) returns ( .echo.EchoResponse );
```

- **Describe a message type**
```sh
$ grpcurl -plaintext localhost:1234 describe echo.EchoRequest
```

**output:**
```
echo.EchoRequest is a message:
message EchoRequest {
  // The text of a message to be echoed.
  string text = 1;
}
```
- 

-**Sending a request to the HelloWorld service**
```sh
$ grpcurl -d '{ "name": "World" }' -plaintext localhost:1234 helloworld.Greeter.SayHello
```

**output:**
```
{
  "message": "Hello World!"
}
```

Note that when specifying a service, a method or a symbol, we have to use the fully qualified names:
- service: \<package\>.\<service\>
- method: \<package\>.\<service\>.\<method\>
- type: \<package\>.\<type\>

[grpcurl-setup]: https://github.com/fullstorydev/grpcurl#grpcurl
[grpc-cli]: https://github.com/grpc/grpc/blob/master/doc/command_line_tool.md
[v1]: ../v1/reflection-v1.proto
[v1alpha]: ../v1Alpha/reflection-v1alpha.proto
[reflectionservice-server]: ../../Examples/ReflectionService/ReflectionServiceServer.swift
[helloworld-proto]: ../Examples/HelloWorld/Model/helloworld.proto
[echo-proto]: ../../../Examples/Echo/Model/echo.proto
