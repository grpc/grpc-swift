#  Reflection Service

The Reflection Service can be added as a provider to any Server. 
In this tutorial we will be using the Server implemented at 
`Sources/Examples/ReflectionService/ReflectionServiceServer.swift`

## GRPCurl setup

## Adding the Reflection Service to a Server

In order to initialize the Reflection Service we need to create the 
file descriptor protos of the proto files that describe the services
we want to be accessible through Server Reflection. A file descriptor
proto is a `Google_Protobuf_FileDescriptorProto` object.

`Google_Protobuf_FileDescriptorProto` objects are initialized using
serialized file descriptor prots, which are generated as binary data
in text files, by the code generator, when setting a sepcific option.


### Generating the serialized file descriptor protos for the Server

The Server used in this example uses the `GreeterProvider` and the 
`ReflectionService`.

In order to generate the serialized file descriptor proto for the
`helloworld.proto`, you can either run the following Makefile
command, or run the same command manually.

Makefile command:
```
$ make generate-helloworld-reflection-data
```

Manual command:
```sh
$ protoc Sources/Examples/HelloWorld/Model/helloworld.proto \
    --proto_path=Sources/Examples/HelloWorld/Model \
    --plugin=./.build/debug/protoc-gen-grpc-swift \
    --grpc-swift_opt=Client=false,Server=false,ReflectionData=true \
    --grpc-swift_out=Sources/Examples/ReflectionService/Generated
```

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

Makefile command for `Echo`:
```
$ make generate-echo-reflection-data
```
Mannual command for `Echo`:
```sh
$ protoc Sources/Examples/Echo/Model/echo.proto \
    --proto_path=Sources/Examples/Echo/Model \
    --plugin=./.build/debug/protoc-gen-grpc-swift \
    --grpc-swift_opt=Client=false,Server=false,ReflectionData=true \
    --grpc-swift_out=Sources/Examples/ReflectionService/Generated
```

Makefile command for `Reflection Service`:
```
$ make generate-reflection-service-reflection-data
```
Mannual command for `Reflection Service`:
```sh
$ protoc Sources/GRPCReflectionService/Model/reflection.proto \
    --proto_path=Sources/GRPCReflectionService/Model \
    --plugin=./.build/debug/protoc-gen-grpc-swift \
    --grpc-swift_opt=Client=false,Server=false,ReflectionData=true \
    --grpc-swift_out=Sources/Examples/ReflectionService/Generated
```


### Instantiating the Reflection Service 

In the Server implementation, we 
## Testing the Reflection Service
- GRPCurl
