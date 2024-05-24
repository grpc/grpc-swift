# gRPC Swift Quick Start

## Before you begin

### Prerequisites

#### Swift Version

gRPC requires Swift 5.8 or higher.

#### Install Protocol Buffers

Install the protoc compiler that is used to generate gRPC service code. The
simplest way to do this is to download pre-compiled binaries for your
platform (`protoc-<version>-<platform>.zip`) from here:
[https://github.com/google/protobuf/releases][protobuf-releases].

* Unzip this file.
* Update the environment variable `PATH` to include the path to the `protoc`
  binary file.

### Download the example

You'll need a local copy of the example code to work through this quickstart.
Download the example code from our GitHub repository (the following command
clones the entire repository, but you just need the examples for this quickstart
and other tutorials):

```sh
$ # Clone the repository at the latest release to get the example code (replacing x.y.z with the latest release, for example 1.13.0):
$ git clone -b x.y.z https://github.com/grpc/grpc-swift
$ # Navigate to the repository
$ cd grpc-swift/
```

## Run a gRPC application

From the `grpc-swift` directory:

1. Compile and run the server

   ```sh
   $ swift run HelloWorldServer
   ```

2. In another terminal, compile and run the client

   ```sh
   $ swift run HelloWorldClient
   Greeter received: Hello stranger!
   ```

Congratulations! You've just run a client-server application with gRPC.

## Update a gRPC service

Now let's look at how to update the application with an extra method on the
server for the client to call. Our gRPC service is defined using protocol
buffers; you can find out lots more about how to define a service in a `.proto`
file in [What is gRPC?][grpc-guides]. For now all you need to know is that both
the server and the client "stub" have a `SayHello` RPC method that takes a
`HelloRequest` parameter from the client and returns a `HelloReply` from the
server, and that this method is defined like this:

```proto
// The greeting service definition.
service Greeter {
  // Sends a greeting.
  rpc SayHello (HelloRequest) returns (HelloReply) {}
}

// The request message containing the user's name.
message HelloRequest {
  string name = 1;
}

// The response message containing the greetings.
message HelloReply {
  string message = 1;
}
```

Let's update this so that the `Greeter` service has two methods. Edit
`Protos/upstream/grpc/examples/helloworld.proto` and update it with a new
`SayHelloAgain` method, with the same request and response types:

```proto
// The greeting service definition.
service Greeter {
  // Sends a greeting.
  rpc SayHello (HelloRequest) returns (HelloReply) {}
  // Sends another greeting.
  rpc SayHelloAgain (HelloRequest) returns (HelloReply) {}
}

// The request message containing the user's name.
message HelloRequest {
  string name = 1;
}

// The response message containing the greetings.
message HelloReply {
  string message = 1;
}
```

(Don't forget to save the file!)

### Update and run the application

We need to regenerate
`Sources/Examples/HelloWorld/Model/helloworld.grpc.swift`, which
contains our generated gRPC client and server classes.

From the `grpc-swift` directory run

```sh
$ Protos/generate.sh
```

This also regenerates classes for populating, serializing, and retrieving our
request and response types.

However, we still need to implement and call the new method in the human-written
parts of our example application.

#### Update the server

In the same directory, open
`Sources/Examples/HelloWorld/Server/GreeterProvider.swift`. Implement the new
method like this:

```swift
final class GreeterProvider: Helloworld_GreeterAsyncProvider {
  let interceptors: Helloworld_GreeterServerInterceptorFactoryProtocol? = nil

  func sayHello(
    request: Helloworld_HelloRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Helloworld_HelloReply {
    let recipient = request.name.isEmpty ? "stranger" : request.name
    return Helloworld_HelloReply.with {
      $0.message = "Hello \(recipient)!"
    }
  }

  func sayHelloAgain(
    request: Helloworld_HelloRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Helloworld_HelloReply {
    let recipient = request.name.isEmpty ? "stranger" : request.name
    return Helloworld_HelloReply.with {
      $0.message = "Hello again \(recipient)!"
    }
  }
}
```

#### Update the client

In the same directory, open
`Sources/Examples/HelloWorld/Client/HelloWorldClient.swift`. Call the new method like this:

```swift
func run() async throws {
    // Setup an `EventLoopGroup` for the connection to run on.
    //
    // See: https://github.com/apple/swift-nio#eventloops-and-eventloopgroups
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    // Make sure the group is shutdown when we're done with it.
    defer {
      try! group.syncShutdownGracefully()
    }

    // Configure the channel, we're not using TLS so the connection is `insecure`.
    let channel = try GRPCChannelPool.with(
      target: .host("localhost", port: self.port),
      transportSecurity: .plaintext,
      eventLoopGroup: group
    )

    // Close the connection when we're done with it.
    defer {
      try! channel.close().wait()
    }

    // Provide the connection to the generated client.
    let greeter = Helloworld_GreeterAsyncClient(channel: channel)

    // Form the request with the name, if one was provided.
    let request = Helloworld_HelloRequest.with {
      $0.name = self.name ?? ""
    }

    do {
      let greeting = try await greeter.sayHello(request)
      print("Greeter received: \(greeting.message)")
    } catch {
      print("Greeter failed: \(error)")
    }

    do {
      let greetingAgain = try await greeter.sayHelloAgain(request)
      print("Greeter received: \(greetingAgain.message)")
    } catch {
      print("Greeter failed: \(error)")
    }
  }
```

#### Run!

Just like we did before, from the top level `grpc-swift` directory:

1. Compile and run the server

   ```sh
   $ swift run HelloWorldServer
   ```

2. In another terminal, compile and run the client

   ```sh
   $ swift run HelloWorldClient
   Greeter received: Hello stranger!
   Greeter received: Hello again stranger!
   ```

### What's next

- Read a full explanation of how gRPC works in [What is gRPC?][grpc-guides] and
  [gRPC Concepts][grpc-concepts]
- Work through a more detailed tutorial in [gRPC Basics: Swift][basic-tutorial]

[grpc-guides]: https://grpc.io/docs/guides/
[grpc-concepts]: https://grpc.io/docs/guides/concepts/
[protobuf-releases]: https://github.com/google/protobuf/releases
[basic-tutorial]: ./basic-tutorial.md
