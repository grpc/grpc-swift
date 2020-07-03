# `protoc` Swift gRPC plugin

gRPC Swift provides a plugin for the [protocol buffer][protocol-buffers]
compiler `protoc` to generate classes for clients and services.

## Building the Plugin

The `protoc-gen-grpc-swift` plugin can be built by using the Makefile in the
top-level directory:

```sh
$ make plugins
```

The Swift Package Manager may also be invoked directly to build the plugin:

```sh
$ swift build --product protoc-gen-grpc-swift
```

The plugin must be in your `PATH` environment variable or specified directly
when invoking `protoc`.

## Plugin Options

The table below lists the options available to the `protoc-gen-grpc-swift`
plugin:

| Flag                      | Values                                    | Default    | Description
|:--------------------------|:------------------------------------------|:-----------|:----------------------------------------------------------------------------------------------------------------------
| `Visibility`              | `Internal`/`Public`                       | `Internal` | ACL of generated code
| `Server`                  | `true`/`false`                            | `true`     | Whether to generate server code
| `Client`                  | `true`/`false`                            | `true`     | Whether to generate client code
| `TestClient`              | `true`/`false`                            | `false`    | Whether to generate test client code. Ignored if `Client` is `false`.
| `FileNaming`              | `FullPath`/`PathToUnderscores`/`DropPath` | `FullPath` | How to handle the naming of generated sources, see [documentation][swift-protobuf-filenaming]
| `ExtraModuleImports`      | `String`                                  |            | Extra module to import in generated code. This parameter may be included multiple times to import more than one module
| `ProtoPathModuleMappings` | `String`                                  |            | The path of the file that contains the module mappings for the generated code, see [swift-protobuf documentation](https://github.com/apple/swift-protobuf/blob/master/Documentation/PLUGIN.md#generation-option-protopathmodulemappings---swift-module-names-for-proto-paths)

To pass extra parameters to the plugin, use a comma-separated parameter list
separated from the output directory by a colon. Alternatively use the
`--grpc-swift_opt` flag.

For example, to generate only client stubs:

```sh
protoc <your proto> --grpc-swift_out=Client=true,Server=false:.
```

Or, in the alternate syntax:

```sh
protoc <your proto> --grpc-swift_opt=Client=true,Server=false --grpc-swift_out=.
```

[protocol-buffers]: https://developers.google.com/protocol-buffers/docs/overview
[swift-protobuf-filenaming]: https://github.com/apple/swift-protobuf/blob/master/Documentation/PLUGIN.md#generation-option-filenaming---naming-of-generated-sources
