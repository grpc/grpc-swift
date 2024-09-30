# Generating stubs

Learn how to generate stubs for gRPC Swift from a service defined using the Protocol Buffers IDL.

## Using protoc

If you've used Protocol Buffers before then generating gRPC Swift stubs should be simple. If you're
unfamiliar with Protocol Buffers then you should get comfortable with the concepts before
continuing; the [Protocol Buffers website](https://protobuf.dev/) is a great place to start.

The [`grpc-swift-protobuf`](https://github.com/grpc/grpc-swift-protobuf) package provides
`protoc-gen-grpc-swift`, a program which is a plugin for the Protocol Buffers compiler, `protoc`.

> `protoc-gen-grpc-swift` only generates gRPC stubs, it doesn't generate messages. You must use
> `protoc-gen-swift` to generate messages in addition to gRPC Stubs.

To generate gRPC stubs for your `.proto` files you must run the `protoc` command with
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

### Generator options

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

### Building the plugin

> The version of `protoc-gen-grpc-swift` you use mustn't be newer than the version of
> the `grpc-swift-protobuf` you're using.

If your package depends on `grpc-swift-protobuf` then you can get a copy of `protoc-gen-grpc-swift`
by building it directly:

```console
swift build --product protoc-gen-grpc-swift
```

This command will build the plugin into `.build/debug` directory. You can get the full path using
`swift build --show-bin-path`.
