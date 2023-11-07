# ReflectionServiceTutorial

This tutorial goes through the process of adding the Reflection Service to a 
 Swift Server and testing it using [GRPCurl]. 

  The Server used in this example is implemented at 
 `Sources/Examples/ReflectionService/ReflectionServiceServer.swift`
 and it exposes the `Greeter` provider, the `Echo` provider and the 
 `ReflectionService` provider. 


## Adding the Reflection Service to a Server

The Reflection Service provider has two initialisers:
- ``init(fileDescriptors: [Google_Protobuf_FileDescriptorProto])``:
  Receives the file descriptor protos of the proto files describing
  the services of the Server that we want to be discoverable 
  through reflection.
- ``init(filePaths: [String])``:
  Receives the paths to the files containing the base64 encoded 
  serialized file descriptor protos of the proto files describing 
  the services of the Server that we want to be discoverable through reflection.

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
for: ``Sources/Examples/HelloWorld/Model/helloworld.proto``.
- The `proto_path` flag is the path to search for imports: 
``Sources/Examples/HelloWorld/Model``.
- The plugin we are using is `./.build/debug/protoc-gen-grpc-swift`.
- The options for the `grpc-swift_opt` flag that we should set are:
`Client=false,Server=false`, because we don't want to generate code
and `ReflectionData=true` to signal that we want to generate a
file containing the serialized file descriptor proto.
- The `grpc-swift_out` flag sets the 

Running this command generates the `helloworld.grpc.reflection.txt`
in the `Sources/Examples/ReflectionService/Generated` folder.
The file contains the serialized file descriptor proto of `helloworld.proto`.

We invoke the protocol buffer compiler `protoc` with the path to the
 service definition `helloworld.proto`, and the path to the folder of the
 proto as the path to search for imports. Then, the `protoc-gen-grpc-swift`
 plugin for the code generation is specified. For the options, we
 disable the generation of Client and Server code (`Client=false,Server=false`),
  but we enable the serialized file descriptor proto generation, through
 the `ReflectionData=true` option.
 Lastly, we specify the folder path of the binary file, in this case:
 `Sources/Examples/ReflectionService/Generated`.

Similarly, we generate the `Echo` and `Reflection` services' serialized 
 file descriptor protos.



 ### Instantiating the Reflection Service 

 In the Server implementation, we 


 ## Testing the Reflection Service

 ### GRPCurl setup
 Please follow the instructions from the GRPCurl Readme [] in order to set ot up.
