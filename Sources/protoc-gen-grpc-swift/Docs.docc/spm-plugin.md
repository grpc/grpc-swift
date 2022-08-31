# Using the Swift Package Manager plugin

The Swift Package Manager introduced new plugin capabilities in Swift 5.6, enabling the extension of
the build process with custom build tools. Learn how to use the `GRPCSwiftPlugin` plugin for the
Swift Package Manager.

## Overview

> Warning: Due to limitations of binary executable discovery with Xcode we only recommend using the Swift Package Manager
plugin in leaf packages. For more information, read the `Defining the path to the protoc binary` section of
this article.

The plugin works by running the system installed `protoc` compiler with the `protoc-gen-grpc-swift` plugin
for specified `.proto` files in your targets source folder. Furthermore, the plugin allows defining a
configuration file which will be used to customize the invocation of `protoc`.

### Installing the protoc compiler

First, you must ensure that you have the `protoc` compiler installed.
There are multiple ways to do this. Some of the easiest are:

1. If you are on macOS, installing it via `brew install protoc`
2. Download the binary from [Google's github repository](https://github.com/protocolbuffers/protobuf).

### Adding the proto files to your target

Next, you need to add the `.proto` files for which you want to generate your Swift types to your target's
source directory. You should also commit these files to your git repository since the generated types
are now generated on demand.

> Note: imports on your `.proto` files will have to include the relative path from the target source to the `.proto` file you wish to import.

### Adding the plugin to your manifest

After adding the `.proto` files you can now add the plugin to the target inside your `Package.swift` manifest.
First, you need to add a dependency on `grpc-swift`. Afterwards, you can declare the usage of the plugin
for your target. Here is an example snippet of a `Package.swift` manifest:

```swift
let package = Package(
  name: "YourPackage",
  products: [...],
  dependencies: [
    ...
    .package(url: "https://github.com/grpc/grpc-swift", from: "1.10.0"),
    ...
  ],
  targets: [
    ...
    .executableTarget(
        name: "YourTarget",
        plugins: [
            .plugin(name: "GRPCSwiftPlugin", package: "grpc-swift")
        ]
    ),
    ...
)

```

### Configuring the plugin

Lastly, after you have added the `.proto` files and modified your `Package.swift` manifest, you can now
configure the plugin to invoke the `protoc` compiler. This is done by adding a `grpc-swift-config.json`
to the root of your target's source folder. An example configuration file looks like this:

```json
{
    "invocations": [
        {
            "protoFiles": [
                "Path/To/Foo.proto",
            ],
            "visibility": "internal",
            "server": false
        },
        {
            "protoFiles": [
                "Bar.proto"
            ],
            "visibility": "public",
            "client": false,
            "keepMethodCasing": false
        }
    ]
}

```

In the above configuration, you declared two invocations to the `protoc` compiler. The first invocation
is generating Swift types for the `Foo.proto` file with `internal` visibility. The second invocation
is generating Swift types for the `Bar.proto` file with the `public` visibility.

> Note: paths to your `.proto` files will have to include the relative path from the target source to the `.proto` file location. 

### Defining the path to the protoc binary

The plugin needs to be able to invoke the `protoc` binary to generate the Swift types. 
There are two ways how this can be achieved. First, by default, the package manager looks into
the `$PATH` to find binaries named `protoc`. This works immediately if you use `swift build` to build
your package and `protoc` is installed in the `$PATH` (`brew` is adding it to your `$PATH` automatically).
However, this may not work if you want to compile from Xcode since Xcode is not passed the `$PATH` by default.
To still make this work from Xcode you can point the plugin to the concrete location of the `protoc`
compiler by changing the configuration file like this:

```json
{
    "protocPath": "/path/to/protoc",
    "invocations": [...]
}
```

> Warning: This only solves the problem for leaf packages that are using the Swift package manager
plugin since there you can point the package manager to the right binary. If your package is **NOT** a
leaf package and should build with Xcode, we advise not to adopt the plugin yet!

An alternative to the above is to start Xcode by running `$ xed .` from the command line from the directory
your project is located.
