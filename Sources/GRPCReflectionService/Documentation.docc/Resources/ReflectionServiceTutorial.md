# ReflectionServiceTutorial

This tutorial goes through the process of running a Server that supports
Reflection and testing it using GRPCurl. 

 The Server used in this example is implemented at 
 `Sources/Examples/ReflectionService/ReflectionServiceServer.swift`
 and it supports the `HelloWord`, `Echo`, and `Reflection` services. 

## Adding the Reflection Service to a Server

The Reflection Service provider has two initialisers:
- init(fileDescriptors: [Google_Protobuf_FileDescriptorProto], version: ):
  Receives as parameters the file descriptor protos of the proto files describing
  the services of the Server that we want to be discoverable 
  through reflection and the version of the reflection service.
- init(filePaths: [String], version: ):
  Receives the paths to the files containing the base64 encoded 
  serialized file descriptor protos of the proto files describing 
  the services of the Server that we want to be discoverable through reflection
  and the version of the reflection service.

The latter is more convinient for the users, so we will use it in this example as well.
Before initialising the ReflectionService provider we need to generate the
files containing the base64 encoded serialized file descriptor protos.


### Generating the serialized file descriptor protos for the Server
 The Server from this example uses the `GreeterProvider`, `EchoProvider` and the 
 `ReflectionService`. The associated proto files are located at 
 `Sources/Examples/HelloWorld/Model/helloworld.proto`, 
 `Sources/Examples/Echo/Model/echo.proto`, and 
 `Sources/GRPCReflectionService/Model/reflection.proto` respectively.

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
- [Sources/GRPCReflectionService/Model/reflection.proto][reflection-proto]

 ### Instantiating the Reflection Service 

 In the Server implementation, we have to instantiate each provider. 

// Link to basic tutorial / quick setup for creating a server

### Running the Server

To start the server, from the root of the package run:

```sh
$ swift run ReflectionServiceserver
```

 ## Testing the Reflection Service using GRPCurl

From a different terminal than the one used for running the Server, 

 ### GRPCurl setup
 Please follow the instructions from the GRPCurl Readme [] in order to set ot up.

[helloworld-proto]: ../../Sources/Examples/HelloWorld/Model/helloworld.proto
[echo-proto]: ../../../Sources/Examples/Echo/Model/echo.proto
[reflection-proto]: ../../Sources/GRPCReflectionService/Model/reflection.proto
