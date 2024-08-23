# Generating stubs

Learn how to generate stubs for gRPC Swift from a service defined using the Protocol Buffers IDL.

## Overview

There are two approaches to generating stubs from Protocol Buffers:

1. With the Swift Package Manager build plugin, or
2. With the Protocol Buffers compiler (`protoc`).

The following sections describe how and when to use each.

### Using the Swift Package Manager build plugin

You can generate stubs at build time by using `GRPCSwiftPlugin` which is a build plugin for the
Swift Package Manager. Using it means that you don't have to manage the generation of
stubs with separate tooling, or check the generated stubs into your source repository.

The build plugin will generate gRPC stubs for you by building `protoc-gen-grpc-swift` (more details
in the following section) for you and invoking `protoc`. Because of the implicit
dependency on `protoc` being made available by the system `GRPCSwiftPlugin` isn't suitable for use
in:

- Library packages, or
- Environments where `protoc` isn't available.

> `GRPCSwiftPlugin` _only_ generates gRPC stubs, it doesn't generate messages. You must generate
> messages in addition to the gRPC Stubs. The [Swift Protobuf](https://github.com/apple/swift-protobuf)
> project provides an equivalent build plugin, `SwiftProtobufPlugin`, for this.

#### Configuring the build plugin

You can configure which stubs `GRPCSwiftPlugin` generates and how via a configuration file. This
must be called `grpc-swift-config.json` and can be placed anywhere in the source directory for your
target.

A config file for the plugin is made up of a number of `protoc` invocations. Each invocation
describes the inputs to `protoc` as well as any options.

The following is a list of options which can be applied to each invocation object:
- `protoFiles`, an array of strings where each string is the path to an input `.proto` file
  _relative to `grpc-swift-config.json`_.
- `visibility`, a string describing the access level of the generated stub (must be one
  of `"public"`, `"internal"`, or `"package"`). If not specified then stubs are generated as
  `internal`.
- `server`, a boolean indicating whether server stubs should be generated. Defaults to `true` if
  not specified.
- `client`, a boolean indicating whether client stubs should be generated. Defaults to `true` if
  not specified.
- `_V2`, a boolean indicated whether the generated stubs should be for v2.x. Defaults to `false` if
  not specified.

> The `GRPCSwiftPlugin` build plugin is currently shared between gRPC Swift v1.x and v2.x. To
> generate stubs for v2.x you _must_ set `_V2` to `true` in your config.
>
> This option will be deprecated and removed once v2.x has been released.

#### Finding protoc

The build plugin requires a copy of the `protoc` binary to be available. To resolve which copy of
the binary to use, `GRPCSwiftPlugin` will look at the following in order:

1. The exact path specified in the `protocPath` property in `grpc-swift-config.json`, if present.
2. The exact path specified in the `PROTOC_PATH` environment variable, if set.
3. The first `protoc` binary found in your `PATH` environment variable.

#### Using the build plugin from Xcode

Xcode doesn't have access to your `PATH` so in order to use `GRPCSwiftPlugin` with Xcode you must
either set `protocPath` in your `grpc-swift-config.json` or explicitly set `PROTOC_PATH` when
opening Xcode.

You can do this by running:

```sh
env PROTOC_PATH=/path/to/protoc xed /path/to/your-project
```

Note that Xcode must _not_ be open before running this command.

#### Example configuration

We recommend putting your config and `.proto` files in a directory called `Protos` within your
target. Here's an example package structure:

```
MyPackage
├── Package.swift
└── Sources
    └── MyTarget
        └── Protos
            ├── foo
            │   └── bar
            │       ├── baz.proto
            │       └── buzz.proto
            └── grpc-swift-config.json
```

If you wanted the generated stubs from `baz.proto` to be `public`, and to only generate a client
for `buzz.proto` then the `grpc-swift-config` could look like this:

```json
{
  "invocations": [
    {
      "_V2": true,
      "protoFiles": ["foo/bar/baz.proto"],
      "visibility": "public"
    },
    {
      "_V2": true,
      "protoFiles": ["foo/bar/buzz.proto"],
      "server": false
    }
  ]
}
```

### Using protoc

If you've used Protocol Buffers before then generating gRPC Swift stubs should be simple. If you're
unfamiliar with Protocol Buffers then you should get comfortable with the concepts before
continuing; the [Protocol Buffers website](https://protobuf.dev/) is a great place to start.

gRPC Swift provides `protoc-gen-grpc-swift`, a program which is a plugin for the Protocol Buffers
compiler, `protoc`.

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

#### Generator options

| Name                      | Possible Values                            | Default    | Description                                              |
|---------------------------|--------------------------------------------|------------|----------------------------------------------------------|
| `_V2`                     | `True`, `False`                            | `False`    | Whether stubs are generated for gRPC Swift v2.x          |
| `Visibility`              | `Public`, `Package`, `Internal`            | `Internal` | Access level for generated stubs                         |
| `Server`                  | `True`, `False`                            | `True`     | Generate server stubs                                    |
| `Client`                  | `True`, `False`                            | `True`     | Generate client stubs                                    |
| `FileNaming`              | `FullPath`, `PathToUnderscore`, `DropPath` | `FullPath` | How generated source files should be named. (See below.) |
| `ProtoPathModuleMappings` |                                            |            | Path to module map `.asciipb` file. (See below.)         |
| `AccessLevelOnImports`    | `True`, `False`                            | `True`     | Whether imports should have explicit access levels.      |

> The `protoc-gen-grpc-swift` binary is currently shared between gRPC Swift v1.x and v2.x. To
> generate stubs for v2.x you _must_ specify `_V2=True`.
>
> This option will be deprecated and removed once v2.x has been released.

The `FileNaming` option has three possible values, for an input of `foo/bar/baz.proto` the following
output file will be generated:
- `FullPath`: `foo/bar/baz.grpc.swift`.
- `PathToUnderscore`: `foo_bar_baz.grpc.swift`
- `DropPath`: `baz.grpc.swift`

The code generator assumes all inputs are generated into the same module, `ProtoPathModuleMappings`
allows you to specify a mapping from `.proto` files to the Swift module they are generated in. This
allows the code generator to add appropriate imports to your generated stubs. This is described in
more detail in the [SwiftProtobuf documentation](https://github.com/apple/swift-protobuf/blob/main/Documentation/PLUGIN.md).

#### Building the plugin

> The version of `protoc-gen-grpc-swift` you use mustn't be newer than the version of
> the `grpc-swift` you're using.

If your package depends on `grpc-swift` then you can get a copy of `protoc-gen-grpc-swift`
by building it directly:

```console
swift build --product protoc-gen-grpc-swift
```

This command will build the plugin into `.build/debug` directory. You can get the full path using
`swift build --show-bin-path`.
