[![Build Status](https://travis-ci.org/grpc/grpc-swift.svg?branch=nio)](https://travis-ci.org/grpc/grpc-swift)

# gRPC Swift

This repository contains a gRPC Swift API and code generator.

It is intended for use with Apple's [SwiftProtobuf][swift-protobuf] support for
Protocol Buffers. Both projects contain code generation plugins for `protoc`,
Google's Protocol Buffer compiler, and both contain libraries of supporting code
that is needed to build and run the generated code.

APIs and generated code is provided for both gRPC clients and servers, and can
be built either with Xcode or the Swift Package Manager. Support is provided for
all four gRPC API styles (Unary, Server Streaming, Client Streaming, and
Bidirectional Streaming) and connections can be made either over secure (TLS) or
insecure channels.

gRPC Swift is built on top of [Swift NIO][swift-nio] as opposed to the core
library provided by the [gRPC project][grpc].

### Supported Platforms

gRPC Swift's platform support is identical to the [platform support of Swift NIO](https://github.com/apple/swift-nio#supported-platforms).

## Getting Started

There are two parts to gRPC Swift: the gRPC library and an API code generator.

### Getting the gRPC library

Note that this package requires Swift 5.

#### Swift Package Manager

The Swift Package Manager is the preferred way to get gRPC Swift. Simply add the
package dependency to your `Package.swift` and depend on `"GRPC"` in the
necessary targets:

```swift
dependencies: [
  .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.0.0-alpha.6")
]
```

##### Xcode

From Xcode 11 it is possible to [add Swift Package dependencies to Xcode
projects][xcode-spm] and link targets to products of those packages; this is the
easiest way to integrate gRPC Swift with an existing `xcodeproj`.

##### Manual Integration

Alternatively, gRPC Swift can be manually integrated into a project:

1. Build an Xcode project: `swift package generate-xcodeproj`,
1. Add the generated project to your own project, and
1. Add a build dependency on `GRPC`.

#### CocoaPods

CocoaPods support will be added in v1.0.

### Getting the `protoc` Plugins

Binary releases of `protoc`, the Protocol Buffer Compiler, are available on
[GitHub][protobuf-releases].

To build the plugins, run `make plugin` in the main directory. This uses the
Swift Package Manager to build both of the necessary plugins:
`protoc-gen-swift`, which generates Protocol Buffer support code and
`protoc-gen-grpc-swift`, which generates gRPC interface code.

To install these plugins, just copy the two executables (`protoc-gen-swift` and
`protoc-gen-grpc-swift`) that show up in the main directory into a directory that
is part of your `PATH` environment variable. Alternatively the full path to the
plugins can be specified when using `protoc`.

## Using gRPC Swift

### Recommended

The recommended way to use gRPC Swift is to first define an API using the
[Protocol Buffer][protobuf] language and then use the [Protocol Buffer
Compiler][protobuf] and the [Swift Protobuf][swift-protobuf] and [Swift
gRPC](#getting-the-protoc-plugins) plugins to generate the necessary
support code.

### Example

This example demonstrates how to create a simple service which echoes any
requests it receives back to the caller. We will also demonstrate how to call
the service using a generated client.

We will only cover the unary calls in this example. All call types are
demonstrated in the [Echo example][example-echo].

Three main steps are required:

1. Defining the service in the `proto` interface definition language,
1. Generating the service and client code, and
1. Implementing the service code.

#### Defining the Service

The first step is to define our service defined in the [Protocol
Buffer][protobuf] language as follows:

```proto
syntax = "proto3";

// The namespace for our service, we may have multiple services within a
// single package.
package echo;

// The definition of our service.
service Echo {
  // Get takes a single EchoRequest protobuf message as input and returns a
  // single EchoResponse protobuf message in response.
  rpc Get(EchoRequest) returns (EchoResponse) {}
}

// The EchoRequest protobuf message definition.
message EchoRequest {
  // The text of a message to be echoed.
  string text = 1;
}

// The EchoResponse protobuf message definition.
message EchoResponse {
  // The text of an echo response.
  string text = 1;
}
```

#### Generating the Service and Client Code

Once we have defined our service we can generate the necessary code to implement
our service and client.

Models (such as `EchoRequest` and `EchoResponse`) are generated using the
`protoc` plugin provided by [SwiftProtobuf][swift-protobuf]. Assuming the
above definition for the Echo service and models were saved as `echo.proto` and
the `protoc-gen-swift` plugin is available in your `PATH` then the following
will generate the models and write them to `echo.pb.swift` in the current
directory:

```sh
protoc echo.proto --swift_out=.
```

gRPC Swift provides a plugin (`protoc-gen-grpc-swift`) to generate the client
and server for the `Echo` service defined above. It can be invoked to produce
`echo.grpc.swift` as such:

```sh
protoc echo.proto --grpc-swift_out=.
```

By default both the client and service code is generated (see [Plugin
Options](#plugin-options) for more details).

#### Implementing the Service Code

The generated service code includes a protocol called `Echo_EchoProvider` which
defines the set of RPCs that the service offers. The service can be implemented
by creating a class which conforms to the protocol.

```swift
import GRPC
import NIO

class EchoProvider: Echo_EchoProvider {
  func get(request: Echo_EchoRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Echo_EchoResponse> {
    let response = Echo_EchoResponse.with {
      $0.text = "Swift echo get: \(request.text)"
    }
    return context.eventLoop.makeSucceededFuture(response)
  }
}
```

#### Using the Service Provider and Generated Client

Now that we have implemented our service code and generated a client, we can put
it all together.

First we need the appropriate imports:

```swift
import GRPC
import NIO
import Foundation
```

Since this is just a locally hosted example we'll run the server on localhost
port 8080.

```
let host = "localhost"
let port = 8080
```

First we need to start the server and provide the Echo service using the
`EchoProvider` we implemented above. We create an [event loop
group][nio-ref-elg] which will spawn a single thread to run events on the
server. Note that you can also use `System.coreCount` to get the number of
logical cores on your system.

We also `wait` for the server to start before setting up a client.

```swift
let serverEventLoopGroup = PlatformSupport.makeEventLoopGroup(loopCount: 1)
let configuration = Server.Configuration(
  target: .hostAndPort(host, port),
  eventLoopGroup: serverEventLoopGroup,
  serviceProviders: [EchoProvider()]
)

let server = try Server.start(configuration: configuration).wait()
```

Note that the at the end of the program, the `serverEventLoopGroup` whould be
shutdown (`try serverEventLoopGroup.syncShutdownGracefully()`).

Normally the client would be in a different binary to the server, however, for
this example we will include them together.

Once the server has started we can create a client by defining the connection
configuration, starting the connection, and then using that connection as a
means to make gRPC calls via a generated client. Note that
`Echo_EchoServiceClient` is the client we generated from `echo.proto`.

```swift
let clientEventLoopGroup = PlatformSupport.makeEventLoopGroup(loopCount: 1)
let configuration = ClientConnection.Configuration(
  target: .hostAndPort(host, port),
  eventLoopGroup: clientEventLoopGroup
)

let connection = ClientConnection(configuration: configuration)
// This is our generated client, we only need to pass it a connection.
let echo = Echo_EchoServiceClient(connection: connection)
```

Note that the `clientEventLoopGroup` should also be shutdown when it is no
longer required.

We can also define some options on our call, such as custom metadata and a
timeout. Note that options are not required at the call-site and may be omitted
entirely. If options are omitted from the call then they are taken from the
client instead. Default client options may be passed as an additional argument
to the generated client.

```swift
var callOptions = CallOptions()
// Add a request id header to the call.
callOptions.customMetadata.add(name: "x-request-id", value: UUID().uuidString)
// Set the timeout to 5 seconds. This may throw since the timeout is validated against
// the gRPC specification, which limits timeouts to be at most 8 digits long.
callOptions.timeout = try .seconds(5)
```

We can now make an asynchronous call to the service by using the functions on
the generated client:

```swift
let request = Echo_EchoRequest.with {
  $0.text = "Hello!"
}

let get = echo.get(request, callOptions: callOptions)
```

The returned `get` object is of type `UnaryClientCall<Echo_EchoRequest, Echo_EchoResponse>`
and has [futures][nio-ref-elf] for the initial metadata, response, trailing
metadata and call status. The differences between call types is detailed in
[API Types](#api-types).

Note that the call can be made synchronous by waiting on the `response` property
of the `get` object:

```swift
let response = try get.response.wait()
```

We can register callbacks on the response to observe its value:

```swift
get.response.whenSuccess { response in
  print("Received '\(response.text)' from the Echo service")
}
```

We can also register a callback on the response to observe an error should the
call fail:

```swift
get.response.whenFailure { error in
  print("The Get call to the Echo service failed: \(error)")
}
```

The call will always terminate with a status which includes a status code and
optionally a message and trailing metadata.

This is often the most useful way to determine the outcome of a call. However,
it should be noted that **even if the call fails, the `status` future will be
_succeeded_**.

```swift
get.status.whenSuccess { status in
  if let message = status.message {
    print("Get completed with status code \(status.code) and message '\(message)'")
  } else {
    print("Get completed with status code \(status.code)")
  }
}
```

If the program succeeds it should emit the following output (if you're running
the example the program may terminate before the callbacks are called, to avoid
this you can simply `wait()` on the call status):

```
Received 'Swift echo get: Hello!' from the Echo service
Get completed with status code ok and message 'OK'
```

### Without a Generated Client

It is also possible to call gRPC services without a generated client. The models
for the requests and responses are required, however.

If you are calling a service which you don't have any generated client, you can
use `AnyServiceClient`. For example, to call "Get" on the Echo service you can
do the following:

```swift
let connection = ... // get a ClientConnection
let anyService = AnyServiceClient(connection: connection)

let get = anyService.makeUnaryCall(
  path: "/echo.Echo/Get",
  request: Echo_EchoRequest.with { $0.text = "Hello!" },
  responseType: Echo_EchoResponse.self
)
```

Calls for client-, server- and bidirectional-streaming are done in a similar way
using `makeClientStreamingCall`, `makeServerStreamingCall`, and
`makeBidirectionalStreamingCall` respectively.

These methods are also available on generated clients, allowing you to call
methods which have been added to the service since the client was generated.

### API Types

gRPC Swift provides all four API styles: Unary, Server Streaming, Client
Streaming, and Bidirectional Streaming. Calls to the generated types will return
an object of the approriate type:

- `UnaryCall<Request, Response>`
- `ClientStreamingCall<Request, Response>`
- `ServerStreamingCall<Request, Response>`
- `BidirectionalStreamingCall<Request, Response>`

Each call object provides [futures][nio-ref-elf] for the initial metadata,
trailing metadata, and status. _Unary response_ calls also have a future for the
response whilst _streaming response_ calls will call a handler for each response.
Calls with _unary requests_ send their message when instantiating the call,
_streaming request_ calls include methods on the call object to send messages
(`sendMessage(_:)`, `sendMessages(_:)`, `sendMessage(_:promise:)`,
`sendMessages(_:promise:)`) as well as methods for terminating the stream of
messages (`sendEnd()` and `sendEnd(promise:)`).

These differences are summarised in the following table.

| API Type                | Response | Send Message
|:------------------------|:---------|:------------------
| Unary                   | Future   | At call time
| Client Streaming        | Future   | On the call object
| Server Streaming        | Handler  | At call time
| Bidirectional Streaming | Handler  | On the call object

### Using TLS

gRPC calls can be made over a secure channel by configuring TLS. This requires
specifying `tls` on `ClientConnection.Configuration` or
`Server.Configuration`.

For the client, `tls` can be as simple as:

```swift
let tls = ClientConnection.Configuration.TLS()
```

For the server, `tls` is slightly more complicated as it requires a certificate
chain and private key:

```swift
# Load the certificates from "cert.pem"
let certificates: [NIOSSLCertificate] = try NIOSSLCertificate.fromPEMFile("cert.pem")

let tls = Server.Configuration.TLS(
  certificateChain: certificates.map { .certificate($0) },
  privateKey: .file("key.pem")
)
```

The `TLS` configuration is a subset of [`TLSConfiguration`][nio-ref-tlsconfig]
provided by `NIOSSL` to ensure it meets the gRPC specification. Users may also
initialize `TLS` with `TLSConfiguration` should they require.

### NIO vs. NIO Transport Services

NIO offers extensions to provide first-class support for Apple platforms (iOS
12+, macOS 10.14+, tvOS 12+, watchOS 6+) via [NIO Transport Services][nio-ts].
NIO Transport Services uses [Network.framework][network-framework] and
`DispatchQueue`s to schedule tasks.

To use NIO Transport Services in gRPC Swift you need to provide a
`NIOTSEventLoopGroup` to the configuration of your server or client connection.
gRPC Swift provides a helper method to provide the correct `EventLoopGroup`
based on the network preference:

```swift
PlatformSupport.makeEventLoopGroup(loopCount:networkPreference:) -> EventLoopGroup
```

Here `networkPreference` defaults to `.best`, which chooses the
`.networkFramework` implementation if it is available (iOS 12+, macOS 10.14+,
tvOS 12+, watchOS 6+) and uses `.posix` otherwise.

Using the TLS provided by `Network.framework` via NIO Transport Services is not
currently supported. Instead, TLS is provided by `NIOSSL`.

### Plugin Options

To pass extra parameters to the plugin, use a comma-separated parameter list
separated from the output directory by a colon.

| Flag                 | Values                                    | Default    | Description
|:---------------------|:------------------------------------------|:-----------|:----------------------------------------------------------------------------------------------------------------------
| `Visibility`         | `Internal`/`Public`                       | `Internal` | ACL of generated code
| `Server`             | `true`/`false`                            | `true`     | Whether to generate server code
| `Client`             | `true`/`false`                            | `true`     | Whether to generate client code
| `FileNaming`         | `FullPath`/`PathToUnderscores`/`DropPath` | `FullPath` | How to handle the naming of generated sources, see [documentation][swift-protobuf-filenaming]
| `ExtraModuleImports` | `String`                                  |            | Extra module to import in generated code. This parameter may be included multiple times to import more than one module

For example, to generate only client stubs:

```sh
protoc <your proto> --grpc-swift_out=Client=true,Server=false:.
```

## License

gRPC Swift is released under the same license as [gRPC][grpc], repeated in
[LICENSE](LICENSE).

## Contributing

Please get involved! See our [guidelines for contributing](CONTRIBUTING.md).


[example-echo]: Sources/Examples/Echo
[grpc]: https://github.com/grpc/grpc
[network-framework]: https://developer.apple.com/documentation/network
[nio-ref-elf]: https://apple.github.io/swift-nio/docs/current/NIO/Classes/EventLoopFuture.html
[nio-ref-elg]: https://apple.github.io/swift-nio/docs/current/NIO/Protocols/EventLoopGroup.html
[nio-ref-tlsconfig]: https://apple.github.io/swift-nio-ssl/docs/current/NIOSSL/Structs/TLSConfiguration.html
[nio-ts]: https://github.com/apple/swift-nio-transport-services
[protobuf-releases]: https://github.com/protocolbuffers/protobuf/releases
[protobuf]: https://github.com/google/protobuf
[swift-nio]: https://github.com/apple/swift-nio
[swift-protobuf-filenaming]: https://github.com/apple/swift-protobuf/blob/master/Documentation/PLUGIN.md#generation-option-filenaming---naming-of-generated-sources
[swift-protobuf]: https://github.com/apple/swift-protobuf
[xcode-spm]: https://help.apple.com/xcode/mac/current/#/devb83d64851
