# Generating stubs

Learn how to generate stubs for gRPC Swift from a service defined using the Protocol Buffers IDL.

## Overview

If you've used Protocol Buffers before then generating gRPC Swift stubs should be simple. If you're
unfamiliar with Protocol Buffers then you should get comfortable with the concepts before
continuing; the [Protocol Buffers website](https://protobuf.dev/) is a great place to start.

The [`grpc-swift-protobuf`](https://github.com/grpc/grpc-swift-protobuf) package provides
`protoc-gen-grpc-swift`, a program which is a plugin for the Protocol Buffers compiler, `protoc`.

You can use the protoc plugin from the command line directly, or you can make use of a 
 [Swift Package Manager build plugin](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/Plugins.md) 
convenience which adds the stub generation to the Swift build graph.
You may use the build plugin either from the command line or from Xcode.


> `protoc-gen-grpc-swift` only generates gRPC stubs, it doesn't generate messages. You must use
> `protoc-gen-swift` to generate messages in addition to gRPC Stubs.



## Using the build plugin

The build plugin (`GRPCProtobufGenerator`) is a great choice for convenient dynamic code generation, however it does come with some limitations.
Because it generates the gRPC Swift stubs as part of the build it has the requirement that `protoc` must be available 
at compile time. This requirements means it is not a good fit for library authors who do not have
direct control over this.

The build plugin detects `.proto` files in the source tree and invokes `protoc` once for each file 
(caching results and performing the generation as necessary).

### Adoption
You must adopt Swift Package Manager build plugins on a per-target basis by modifying your package manifest 
(`Package.swift` file). To do this, declare the grpc-swift-protobuf package as a dependency and add the plugin 
to your desired targets.

For example, to make use of the plugin for generating gRPC Swift stubs as part of the 
`echo-server` target:
```swift
targets: [
   .executableTarget(
     name: "echo-server",
     dependencies: [
       // ...
     ],
     plugins: [
       .plugin(name: "GRPCProtobufGenerator", package: "grpc-swift-protobuf")
     ]
   )
 ]
```
Once this is done you need to ensure that that the `.proto` files to be used for generation 
are included in the target's source directory and that you have defined at least one configuration file.

### Configuration

You must provide a configuration file in the directory which encloses all `.proto` files (in the same directory or a parent). 
Configuration files, written in JSON, tell the build plugin about the options used for protoc invocations. 
You must name the file grpc-swift-proto-generator-config.json and structure it in the following format:
```json
{
  "generate": {
    "clients": true,
    "servers": true,
    "messages": true,
  },
  "generatedSource": {
    "accessLevelOnImports": false,
    "accessLevel": "internal",
  }
  "protoc": {
    "executablePath": "/opt/homebrew/bin/protoc"
    "importPaths": [
      "../directory_1",
    ],
  },
}
```

The options do not need to be specified and each have default values.

| Name                                   | Possible Values                            | Default      | Description                                         |
|----------------------------------------|--------------------------------------------|--------------|-----------------------------------------------------|
| `generate.servers`                     | `true`, `false`                            | `true`       | Generate server stubs                               |
| `generate.clients`                     | `true`, `false`                            | `true`       | Generate client stubs                               |
| `generate.messages`                    | `true`, `false`                            | `true`       | Generate message stubs                              |
| `generatedSource.accessLevelOnImports` | `true`, `false`                            | `false`      | Whether imports should have explicit access levels  |
| `generatedSource.accessLevel`          | `"public"`, `"package"`, `"internal"`      | `"internal"` | Access level for generated stubs                    |
| `protoc.executablePath`                | N/A                                        | null†        | Path to the `protoc` executable                     |
| `protoc.importPaths`                   | N/A                                        | null‡        | Import paths passed to `protoc`                     |

† The Swift Package Manager build plugin infrastructure will attempt to discover the executable's location if you don't provide one.

‡ If you don't provide any import paths then the path to the configuration file will be used on a per-source-file basis. 

Many of these map to `protoc-gen-grpc-swift` and `protoc-gen-swift` options.

If you require greater flexibility you may specify more than one configuration file.
Configuration files apply to all `.proto` files equal to or below it in the file hierarchy. A configuration file
lower in the file hierarchy supersedes one above it.

### Using protoc

To generate gRPC stubs for your `.proto` files directly you must run the `protoc` command with
the `--grpc-swift_out=<DIRECTORY>` option:

```console
protoc --grpc-swift_out=. my-service.proto
```

The presence of `--grpc-swift_out` tells `protoc` to use the `protoc-gen-grpc-swift` plugin. By
default it'll look for the plugin in your `PATH`. You can also specify the path to the plugin
explicitly:

```console
protoc --plugin=/path/to/protoc-gen-grpc-swift --grpc-swift_out=. my-service.proto
```

You can also specify various option the `protoc-gen-grpc-swift` via `protoc` using
the `--grpc-swift_opt` argument:

```console
protoc --grpc-swift_opt=<OPTION_NAME>=<OPTION_VALUE> --grpc-swift_out=.
```

You can specify multiple options by passing the `--grpc-swift_opt` argument multiple times:

```console
protoc \
  --grpc-swift_opt=<OPTION_NAME1>=<OPTION_VALUE1> \
  --grpc-swift_opt=<OPTION_NAME2>=<OPTION_VALUE2> \
  --grpc-swift_out=.
```

#### Generator options

| Name                      | Possible Values                            | Default    | Description                                              |
|---------------------------|--------------------------------------------|------------|----------------------------------------------------------|
| `Visibility`              | `Public`, `Package`, `Internal`            | `Internal` | Access level for generated stubs                         |
| `Server`                  | `True`, `False`                            | `True`     | Generate server stubs                                    |
| `Client`                  | `True`, `False`                            | `True`     | Generate client stubs                                    |
| `FileNaming`              | `FullPath`, `PathToUnderscore`, `DropPath` | `FullPath` | How generated source files should be named. (See below.) |
| `ProtoPathModuleMappings` |                                            |            | Path to module map `.asciipb` file. (See below.)         |
| `UseAccessLevelOnImports` | `True`, `False`                            | `False`    | Whether imports should have explicit access levels.      |

The `FileNaming` option has three possible values, for an input of `foo/bar/baz.proto` the following
output file will be generated:
- `FullPath`: `foo/bar/baz.grpc.swift`.
- `PathToUnderscore`: `foo_bar_baz.grpc.swift`
- `DropPath`: `baz.grpc.swift`

The code generator assumes all inputs are generated into the same module, `ProtoPathModuleMappings`
allows you to specify a mapping from `.proto` files to the Swift module they are generated in. This
allows the code generator to add appropriate imports to your generated stubs. This is described in
more detail in the [SwiftProtobuf documentation](https://github.com/apple/swift-protobuf/blob/main/Documentation/PLUGIN.md).

#### Building the protoc plugin

> The version of `protoc-gen-grpc-swift` you use mustn't be newer than the version of
> the `grpc-swift-protobuf` you're using.

If your package depends on `grpc-swift-protobuf` then you can get a copy of `protoc-gen-grpc-swift`
by building it directly:

```console
swift build --product protoc-gen-grpc-swift
```

This command will build the plugin into `.build/debug` directory. You can get the full path using
`swift build --show-bin-path`.
