# gRPC Swift 1.x to 2.x migration guide

Learn how to migrate an app from gRPC Swift 1.x to 2.x.

## Overview

The intended audience for this guide is users of the `async` variants of clients
and services from 1.x, not the versions using the older `EventLoopFuture` API.

The guide takes you through a number of steps to migrate your gRPC app
from 1.x to 2.x. You'll use the following strategy:

1. Setup your package so it depends on a local copy of gRPC Swift 1.x and the
   upstream version of 2.x.
2. Generate code for 2.x to alongside generated 1.x code.
3. Incrementally migrate targets to 2.x.
4. Remove the code generated for, and the dependency on 1.x.

You'll do this migration incrementally by staging in a local copy of gRPC Swift
1.x and migrating client and service code on a per service basis. This approach
aims to minimise the number of errors and changes required to get the package
building again. As a practical note, you should commit changes regularly as you
work through the migration, especially when your package is in a compiling
state.

## Requirements

gRPC Swift 2.x has stricter requirements than 1.x. These include:

- Swift 6 or newer.
- Deployment targets of macOS 15+, iOS 18+, tvOS 18+, watchOS 11+ and visionOS 2+.

To make the migration easier a script is available to automate a number of
steps. You should download it now using:

```sh
curl https://raw.githubusercontent.com/grpc/grpc-swift/refs/heads/main/dev/v1-to-v2/v1_to_v2.sh -o v1_to_v2
```

You'll also need to make the `v1_to_v2` script executable:

```sh
chmod +x v1_to_v2
```

## Depending on 1.x and 2.x

The first step in the migration is to modify your package so that it can
temporarily depend on 1.x and 2.x.

### Getting a local copy of 1.x

The exact version of 1.x you need to depend on must be local as Swift packages
can't depend on two different major versions of the same package. Create a
directory in your package called "LocalPackages" and then call `v1_to_v2`:

```sh
mkdir LocalPackages && ./v1_to_v2 clone-v1 LocalPackages
```

This command checks out a copy of 1.x into `LocalPackages` and applies a few
patches to it which are necessary for the migration. You can remove it once
you've finished the migration.

### Using the local copy of 1.x

Now you need to update your package manifest (`Package.swift`) to use the local
copy rather than the copy from GitHub. Replace your package dependency on
"grpc-swift" with the local dependency, and update any target dependencies to
use "grpc-swift-v1" instead of "grpc-swift":

```swift
let package = Package(
  ...
  dependencies: [
    .package(path: "LocalPackages/grpc-swift-v1")
  ],
  targets [
    .executableTarget(
      name: "Application",
      dependencies [
        ...
        .product(name: "GRPC", package: "grpc-swift-v1"),
        ...
      ]
    )
  ]
  ...
)
```

Check your package still builds by running `swift build`. Now's a good time to
commit the changes you've made so far.

### Adding a dependency on 2.x

Next you need to add a dependency on 2.x. In order to do this you'll need to
raise the tools version at the top of the manifest to 6.0 or higher:

```swift
// swift-tools-version: 6.0
```

You also need to set the `platforms` to the following or higher:

```swift
let package = Package(
  name: "...",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
    .tvOS(.v18),
    .watchOS(.v11),
    .visionOS(.v2),
  ],
  ...
)
```

Note that setting or increasing the platforms is an API breaking change.

Check that your package still builds with `swift build`. If you weren't
previously using tools version 6.0 then you're likely to have new warnings or
errors relating to concurrency. You should fix these in the fullness of time
but for now add the `.swiftLanguageMode(.v5)` setting to the `settings` for each
target.

If there are any other build issues fix them up now and commit the changes.

Now add the following package dependencies for gRPC Swift 2.x:

```
.package(url: "https://github.com/grpc/grpc-swift.git", from: "2.0.0"),
.package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0"),
.package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.0.0"),
```

For each target which was previously importing the `GRPC` module add the
following target dependencies:

```
.product(name: "GRPCCore", package: "grpc-swift"),
.product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
.product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
```

Run `swift build` again to verify your package still builds. Now is another
great time to commit your changes.

## Code generation

Now that you've built your package with dependencies on a lightly modified
version of 1.x and 2.x you need to consider the generated code. The approach you
take here depends on how you're currently generating your gRPC code:

1. Using `protoc` directly, or
2. Using the build plugin.

### Using protoc directly

> If you generated your gRPC code with the build plugin then skip this section.

Because the names of the files containing generated gRPC code will be the same
for 1.x and 2.x (and the Swift compiler requires file names to be unique) we need
to rename all of the gRPC code generated by 1.x.

You can use the `v1_to_v2` script to rename all `*.grpc.swift` files to
`*.grpc.v1.swift` by using the `rename-generated-files` subcommand with the
directory containing your generated code, for example:

```sh
./v1_to_v2 rename-generated-files Sources/
```

One of the patches applied to the local copy of 1.x was to rename
`protoc-gen-grpc-swift` to `protoc-gen-grpc-swift-v1`. If you previously used a
script to generate your code, then run it again, ensuring that the copy of
`protoc-gen-grpc-swift` comes from this package (as it will now be for 2.x).

If you didn't use a script to generate your code then refer to the
[documentation][3] to learn how to generate gRPC Swift code.

Check that your package still builds and commit any changes.

### Using the build plugin

> If you generated your gRPC code using `protoc` directly then skip this
> section.

Because you don't have direct control over the names of files generated by the
build plugin you can't rename them directly. Instead our strategy is to locate
the generated gRPC code from the build directory and copy it into the source
directory and then replace the 1.x plugin with the 2.x plugin.

As you've been building your package regularly the generated files should
already be in the `.build` directory. You can find them using:

```sh
find .build/plugins/outputs -name '*.grpc.swift'
```

Move the files for their appropriate directory in `Sources`. Once you've done
that you can use the `v1_to_v2` script to rename all `*.grpc.swift` files to
`*.grpc.v1.swift` by using the `rename-generated-files` subcommand with the
directory containing your generated code, for example:

```sh
./v1_to_v2 rename-generated-files Sources/
```

The next step is to use the new build plugin. The build plugin for 2.x can
generate gRPC code and Protobuf messages, so remove the gRPC Swift 1.x _and_
SwiftProtobuf build plugins from your manifest and replace them with the plugin
for 2.x:

```swift
.target(
  ...
  plugins: [
    .plugin(name: "GRPCProtobufGenerator", package: "grpc-swift-protobuf")
  ]
)
```

Finally you need to add a configuration file for the plugin. Take a look at the
[build plugin documentation][3] for instructions on how to do this.

At this point you should run `swift build` again to check your package still
compiles and commit any changes.

## Service code migration

> If you only need to migrate clients then skip this section.

By now your package should be set up to depend on a patched version of 1.x and 2.x
and have both sets of generated code and still compile. It's time to make some
code changes, so let's start by migrating a service.


A number of these steps can be automated, and the `v1_to_v2` script can do just
this. However, it might not be sufficient and you should read through the
steps below to understand what transformations are done.

Find the service you wish to migrate. The first step is to update any imports
from `GRPC` to `GRPCCore`, which is the base module containing abstractions and
runtime components for 2.x.

Next let's update the service protocol that your type conforms to. In 2.x each
service has three protocols generated for it, each offering a different level of
granularity. You can read more about each version in the [gRPC Swift Protobuf
documentation][2]. The variant most like 1.x is the `SimpleServiceProtocol`.
However, it doesn't allow you access metadata. If you need access to metadata
skip to the section called `ServiceProtocol`.

### SimpleServiceProtocol

The requirements for each methods are also slightly different; in 2.x the context
type is called `ServerContext` as opposed to `GRPCAsyncServerCallContext` in 1.x.
It also has different functionality but that will be covered later. The types
for streaming requests and responses are also different:
- `GRPCAsyncRequestStream<T>` became `RPCAsyncSequence<T, any Error>`, and
- `GRPCAsyncResponseStreamWriter<T>` became `RPCWriter<T>`.

The `v1_to_v2` script has a subcommand to apply all of these transformations to
an input file. Run it now. Here's an example invocation:

```sh
./v1_to_v2 patch-service Sources/Server/Service.swift
```

If the service was contained to that file then that might be the extent of
changes you need to make for that service. However, it's likely that types leak
into other files. If that's the case you should continue applying these
transformations until your app compiles again. You'll also need to stop
passing this service to your 1.x server.

Once you've gotten to a point where the package builds, commit your changes.
Repeat this until you've done all services in your package.

### ServiceProtocol

> If the `SimpleServiceProtocol` worked then you can skip this section.

If you're reading this section then you're likely relying on metadata in your
service. This means you need to implement the `ServiceProtocol` instead of the
`SimpleServiceProtocol` and the transformations you need to apply are
aren't well suited automation. The best approach is to conform your
service to the 1.x protocol and the 2.x protocol. Add conformance to the
`{Service}.ServiceProtocol` where `{Service}` is the namespaced name of your
service (if your service is called `Baz` and declared in the `foo.bar` Protocol
Buffers package then this would be `Foo_Bar_Baz.ServiceProtocol`).

Let Xcode generate stubs for the methods which haven't been implemented yet and
fill each one with a `fatalError` so that you app builds. Each method
should take a `ServerRequest` or `StreamingServerRequest` and context as input
and return a `ServerResponse` or `StreamingServerResponse`. Request metadata is
available on the request object. For single responses you can set initial and
trailing metadata when you create the response. For streaming responses you can
set initial metadata in the initializer and return trailing metadata from the
closure you provide to the initializer.

One important difference between this approach and the `SimpleServiceProtocol`
(and 1.x) is that responses aren't completed until the body of the response has
completed as opposed to when the function returns. This means that much of your
logic likely lives within the body of the `StreamingServerResponse`.

## Server migration

With all services updated to use gRPC Swift 2.x you now need to update the
server. Find where you create the server in your app. In this file
you'll need to add imports for `GRPCCore` (which provides the server type) and
`GRPCNIOTransportHTTP2` (which provides HTTP/2 transports built on top of
SwiftNIO).

The server object is called `GRPCServer` and you initialize it with a transport,
any configuration, and a list of services. Importantly you must call `serve()` to start
the server. This blocks indefinitely so it often makes sense to start it in a
task group if you need to run other code concurrently. Here's an example of a
server configured to use the HTTP/2 transport:

```swift
let server = GRPCServer(
  transport: .http2NIOPosix(
    // Configure the host and port to listen on.
    address: .ipv4(host: "127.0.0.1", port: 1234),
    // Configure TLS here, if your're using it.
    transportSecurity: .plaintext,
    config: .defaults { config in
      // Change any of the default config in here.
    }
  ),
  // List your services here:
  services: []
)

// Start the server.
try await server.serve()
```

You can get the listening address using the `listeningAddress` property:

```swift
try await withThrowingDiscardingTaskGroup { group in
  group.addTask { try await server.serve() }
  if let address = try await server.listeningAddress {
    print("Listening on \(address)")
  }
}
```

With any luck your app should build and your server should run. Yes, you guessed
it, it's time to commit any changes you've made.

## Client code migration

> You can skip this section if you only needed to migrate services.

Migrating client code is more difficult as you typically use client code
throughout a wider part of your app. Our approach is to migrate from client
calls first and then work upwards through your app to where the client is
created.

Start by finding a place within the target being migrated where a generated
client is being used.

Note that the generated client in 2.x is generic over a transport type, any
types or functions using it will either need to choose a concrete type or
also become generic. The most similar replacements to 1.x are:

- `HTTP2ClientTransport.Posix`, and
- `HTTP2ClientTransport.TransportServices`.

Changing the type of the client will cause numerous build errors. To keep the
number of errors manageable you'll migrate one function at a time. How this
is done depends on whether the generated client is passed in to the function
or stored on a property.

If the function is passed a generated client then duplicate it, changing the
signature to use a 2.x generated client. The new client is
named `{Service}.Client` where `{Service}` is the namespaced name of your
service (if your service is named `Baz` and declared in the `foo.bar`
Protocol Buffers package then this would be `Foo_Bar_Baz.Client`).
Change the body of the function using the 1.x client to just `fatalError()`.
Later you'll remove this function altogether.

If the generated client is a stored type then add a new computed property
returning an instance of it, the body can just call `fatalError()` for now:

```swift
var client: Foo_Bar_Baz.Client {
  fatalError("TODO")
}
```

If a generated client is passed into the function then duplicate the function
and replace the body of the new version with a `fatalError()`. You can also mark
it as deprecated to help you find usages of the function. You'll now have two
versions of the same function.

Now you need to update the function to use the new client. For unary calls the API
is very similar, so you may not have to change any code. An important change to
highlight is that for RPCs which stream their responses you must handle the
response stream _within_ the closure passed to the client. By way of example,
imagine the following server streaming RPC from 1.x:

```swift
func serverStreamingEcho(text: String, client: Echo_EchoAsyncClient) async throws {
  for try await reply in client.expand(.with { $0.text = text }) {
    print(reply.text)
  }
}
```

In 2.x this becomes:

```swift
func serverStreamingEcho(text: String, client: Echo_Echo.Client<Transport>) async throws {
  try await client.expand(.with { $0.text = text }) { response in
    for try await reply in response.messages {
      print(reply.text)
    }
  }
}
```

Similarly for client streaming RPCs you must provide any messages within a
closure. Here's an example of 1.x:

```swift
func clientStreamingEcho(text: String, client: Echo_EchoAsyncClient) async throws {
  let messages = makeAsyncSequenceOfMessages(text)
  let reply = try await client.collect(messages)
  print(reply.text)
}
```

The equivalent code in 2.x is:

```swift
func clientStreamingEcho(text: String, client: Echo_Echo.Client<Transport>) async throws {
  let reply = try await client.collect { request in
    for try await message in makeAsyncSequenceOfMessages(text) {
      request.write(message)
    }
  }
  print(reply.text)
}
```

Bidirectional streaming is just a combination of the previous two examples.

Once the new version compiles you can work upwards, updating functions which
pass in the generated client to use the new one instead. You can also remove
any of the unused functions.

## Client migration

Once all client call sites have been updates you'll need to update how you
create the client. Find where you create the client in your app. In this file
you'll need to add imports for `GRPCCore` (which provides the client type) and
`GRPCNIOTransportHTTP2` (which provides HTTP/2 transports built on top of
SwiftNIO).

The client object is called `GRPCClient` and you initialize it with a transport,
and any configuration. Importantly you must call `runConnections()` to start the
client. This runs indefinitely and maintains the connections for the client so
it makes sense to start it in a task group. Alternatively you can use the
`withGRPCClient(transport:interceptors:handleClient:)` helper which provides you
with scoped access to a running client.

Here's an example of a client configured to use the HTTP/2 transport:

```swift
try await withGRPCClient(
  transport: .http2NIOPosix(
    target: .dns(host: "example.com"),
    transportSecurity: .tls,
  )
) { client in
  // ...
}
```

With any luck your app should build and your server should run. Yes, you guessed
it, it's time to commit any changes you've made.

## Cleaning up

Once you've migrated you package you can remove the local checkout of gRPC Swift
1.x and remove it from your package manifest.

## What's missing?

If there were any parts of this guide you felt were unclear or didn't cover enough
of the migration then please file an issue on GitHub so that we can work on improving
it.

[0]: https://github.com/grpc/grpc-swift/tree/main
[1]: https://github.com/grpc/grpc-swift/tree/release/1.x
[2]: https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation
[3]: https://swiftpackageindex.com/grpc/grpc-swift-protobuf/documentation/grpcprotobuf/generating-stubs
