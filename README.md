[![Build Status](https://travis-ci.org/grpc/grpc-swift.svg?branch=master)](https://travis-ci.org/grpc/grpc-swift)

# Swift gRPC

This repository contains an experimental Swift gRPC API
and code generator.

It is intended for use with Apple's
[swift-protobuf](https://github.com/apple/swift-protobuf)
support for Protocol Buffers. Both projects contain
code generation plugins for `protoc`, Google's
Protocol Buffer compiler, and both contain libraries
of supporting code that is needed to build and run
the generated code.

APIs and generated code is provided for both gRPC clients
and servers, and can be built either with Xcode or the Swift
Package Manager. Support is provided for all four gRPC
API styles (Unary, Server Streaming, Client Streaming,
and Bidirectional Streaming) and connections can be made
either over secure (TLS) or insecure channels.

The [Echo](Examples/EchoXcode/Echo) example provides a comprehensive
demonstration of currently-supported features.

Swift Package Manager builds may also be made on Linux
systems. Please see [DOCKER.md](DOCKER.md) and
[LINUX.md](LINUX.md) for details.

## CocoaPods integration

Swift gRPC is currently available [from CocoaPods](https://cocoapods.org/pods/SwiftGRPC).
To integrate, add the following line to your `Podfile`:

    pod 'SwiftGRPC'

Then, run `pod install` from command line and use your project's generated
`.xcworkspace` file.

## Manual integration

When not using CocoaPods, Swift gRPC includes **[vendored copies](./scripts/vendor-all.sh)** of the
gRPC Core library and BoringSSL (an OpenSSL fork that is used by
the gRPC Core). These are built automatically in Swift Package
Manager builds.

After [building your project](#building-your-project), add the generated
`SwiftGRPC.xcodeproj` to your project, and add build dependencies
on **BoringSSL**, **CgRPC**, and **SwiftGRPC**.

Please also note that your project will need to include the
`SwiftProtobuf.xcodeproj` from
[Swift Protobuf](https://github.com/apple/swift-protobuf) and
the source files that you generate with `protoc`/[plugins](#getting-the-plugins).

See [Echo](Examples/EchoXcode) for a working Xcode-based
example, and don't hesitate to file issues if you find any problems.

## Usage

The recommended way to use Swift gRPC is to first define an API using the
[Protocol Buffer](https://developers.google.com/protocol-buffers/)
language and then use the
[Protocol Buffer Compiler](https://github.com/google/protobuf)
and the [Swift Protobuf](https://github.com/apple/swift-protobuf)
and [Swift gRPC](https://github.com/grpc/grpc-swift) plugins to
generate the necessary support code.

### Getting the plugins

Binary releases of `protoc`, the Protocol Buffer Compiler, are
available on [GitHub](https://github.com/google/protobuf/releases).

To build the plugins, run `make plugin` in the main directory.
This uses the Swift Package Manager to build both of the necessary
plugins: `protoc-gen-swift`, which generates Protocol Buffer support code
and `protoc-gen-swiftgrpc`, which generates gRPC interface code.

To install these plugins, just copy the two executables (`protoc-gen-swift` and `protoc-gen-swiftgrpc`) that show up in the main directory into a directory that is part of your `PATH` environment variable.

### Using the plugins

To use the plugins, `protoc` and both plugins should be in your
search path (see above). Invoke them with commands like the following:

    protoc <your proto files> \
        --swift_out=. \
        --swiftgrpc_out=.

By convention the `--swift_out` option invokes the `protoc-gen-swift`
plugin and `--swiftgrpc_out` invokes `protoc-gen-swiftgrpc`.

#### Parameters

To pass extra parameters to the plugin, use a comma-separated parameter list
separated from the output directory by a colon.

| Flag | Values | Default | Description |
|:-|:-|:-|:-|
| `Visibility` | `Internal`/`Public` | `Internal` | ACL of generated code |
| `Server` |  `true`/`false` | `true` | Whether to generate server code |
| `Client` |  `true`/`false` | `true` | Whether to generate client code |
| `Async` |  `true`/`false` | `true` | Whether to generate asynchronous code |
| `Sync` |  `true`/`false` | `true` | Whether to generate synchronous code |
| `Implementations` |  `true`/`false` | `true` | Whether to generate protocols and non-test service code. Toggling this to `false` is mostly useful when combined with `TestStubs=true` to generate files containing only test stub code |
| `TestStubs` |  `true`/`false` | `false` | Whether to generate test stub code |
| `FileNaming` | `FullPath`/`PathToUnderscores`/`DropPath` | `FullPath` | How to handle the naming of generated sources |
| `ExtraModuleImports` |  `String` | `` | Extra module to import in generated code. This parameter may be included multiple times to import more than one module |

Example:

    $ protoc <your proto> --swiftgrpc_out=Client=true,Server=false:.

### Building your project

Most `grpc-swift` development is done with the Swift Package Manager.
For usage in Xcode projects, we rely on the `swift package generate-xcodeproj`
command to generate an Xcode project for the `grpc-swift` core libraries.

The top-level Makefile uses the Swift Package Manager to
generate an Xcode project for the SwiftGRPC package:

    $ make && make project

This will create `SwiftGRPC.xcodeproj`, which you should
add to your project, along with setting the necessary build dependencies
mentioned [above](#manual-integration).

### Low-level gRPC

While the recommended way to use gRPC is with Protocol Buffers
and generated code, at its core gRPC is a powerful HTTP/2-based
communication system that can support arbitrary payloads. As such,
each gRPC library includes low-level interfaces that can be used
to directly build API clients and servers with no generated code.
For an example of this in Swift, please see the
[Simple](Examples/SimpleXcode) example.

### Known issues

The SwiftGRPC implementation that is backed by [gRPC-Core](https://github.com/grpc/grpc)
(and not SwiftNIO) is known to have some connectivity issues on iOS clients - namely, silently
disconnecting (making it seem like active calls/connections are hanging) when switching
between wifi <> cellular or between cellular technologies (3G <> LTE). The root cause of these problems is that the
backing gRPC-Core doesn't get the optimizations made by iOS' networking stack when these
types of changes occur, and isn't able to handle them itself.

There is also documentation of this behavior in [this gRPC-Core readme](https://github.com/grpc/grpc/blob/v1.19.0/src/objective-c/NetworkTransitionBehavior.md).

To aid in this problem, there is a [`ClientNetworkMonitor`](./Sources/SwiftGRPC/Core/ClientNetworkMonitor.swift)
that monitors the device for events that can cause gRPC to disconnect silently. We recommend utilizing this component to
call `shutdown()` (or destroy) any active `Channel` instances, and start new ones when the network is reachable.

Setting the [`keepAliveTimeout` argument](https://github.com/grpc/grpc-swift/blob/0.7.0/Sources/SwiftGRPC/Core/ChannelArgument.swift#L46)
on channels is also encouraged.

Details:
- **Switching between wifi <> cellular:** Channels silently disconnect
- **Switching between 3G <> LTE (etc.):** Channels silently disconnect
- **Network becoming unreachable:** Most times channels will time out after a few seconds, but `ClientNetworkMonitor` will notify of these changes much faster
- **Switching between background <> foreground:** No known issues

Original SwiftGRPC issue: https://github.com/grpc/grpc-swift/issues/337.

## Having build problems?

grpc-swift depends on Swift, Xcode, and swift-protobuf. We are currently
testing with the following versions:

- Xcode 9.1
- Swift 4.0
- swift-protobuf 1.3.1

## `SwiftGRPCNIO` package

`SwiftGRPCNIO` is a clean-room implementation of the gRPC protocol on top of the [`SwiftNIO`](http://github.com/apple/swift-nio) library. This implementation is not yet production-ready as it lacks several things recommended for production use:

- Better test coverage
- Full error handling
- SSL support
- Client support
- Example projects
- iOS support
- Removal of the `libnghttp2` dependency from `SwiftNIOHTTP2`

However, if you are planning to implement a gRPC service based on `SwiftNIO` or the Vapor framework, you might find this package useful. In addition, once ready, this package should provide more predictable and reliable behavior in the future, combined with an improved API and better developer experience.

You may also want to have a look at [this presentation](https://docs.google.com/presentation/d/1Mnsaq4mkeagZSP4mK1k0vewZrJKynm_MCteRDyM3OX8/edit) for more details on the motivation for this package.

## License

grpc-swift is released under the same license as
[gRPC](https://github.com/grpc/grpc), repeated in
[LICENSE](LICENSE).

## Contributing

Please get involved! See our [guidelines for contributing](CONTRIBUTING.md).

### Releasing

When issuing a new release, the following steps should be followed:

1. Run the CocoaPods linter to ensure that there are no new warnings/errors:

    `$ pod spec lint SwiftGRPC.podspec`

1. Update the Carthage Xcode project (diff will need to be checked in with the version bump):

    `$ make project-carthage`

1. Bump the version in the `SwiftGRPC.podspec` file

1. Merge these changes, then create a new `Release` with corresponding `Tag`. Be sure to include a list of changes in the message

1. Push the update to the CocoaPods specs repo:

    `$ pod trunk push`
