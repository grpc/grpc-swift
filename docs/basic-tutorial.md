# Basic Tutorial

This tutorial provides a basic Swift programmer's introduction to working with
gRPC.

By walking through this example you'll learn how to:

- Define a service in a .proto file.
- Generate server and client code using the protocol buffer compiler.
- Use the Swift gRPC API to write a simple client and server for your service.

It assumes that you have read the [Overview][grpc-docs] and are familiar
with [protocol buffers][protocol-buffers]. Note that the example in this
tutorial uses the [proto3][protobuf-releases] version of the protocol
buffers language: you can find out more in the [proto3 language
guide][protobuf-docs].


### Why use gRPC?

Our example is a simple route mapping application that lets clients get
information about features on their route, create a summary of their route, and
exchange route information such as traffic updates with the server and other
clients.

With gRPC we can define our service once in a .proto file and implement clients
and servers in any of gRPC's supported languages, which in turn can be run in
environments ranging from servers inside Google to your own tablet - all the
complexity of communication between different languages and environments is
handled for you by gRPC. We also get all the advantages of working with protocol
buffers, including efficient serialization, a simple IDL, and easy interface
updating.

### Example code and setup

The example code for our tutorial is in
[grpc/grpc-swift/Sources/Examples/RouteGuide][routeguide-source].
To download the example, clone the latest release in `grpc-swift` repository by
running the following command:

```sh
$ git clone -b 1.0.0-alpha.9 https://github.com/grpc/grpc-swift
```

Then change your current directory to `grpc-swift/Sources/Examples/RouteGuide`:

```sh
$ cd grpc-swift/Sources/Examples/RouteGuide
```


### Defining the service

Our first step (as you'll know from the [Overview][grpc-docs]) is to
define the gRPC *service* and the method *request* and *response* types using
[protocol buffers][protocol-buffers]. You can see the complete .proto file in
[`grpc-swift/Sources/Examples/RouteGuide/Model/route_guide.proto`][routeguide-proto].

To define a service, we specify a named `service` in the .proto file:

```proto
service RouteGuide {
   ...
}
```

Then we define `rpc` methods inside our service definition, specifying their
request and response types. gRPC lets you define four kinds of service methods,
all of which are used in the `RouteGuide` service:

- A *simple RPC* where the client sends a request to the server using the stub
  and waits for a response to come back, just like a normal function call.

```proto
// Obtains the feature at a given position.
rpc GetFeature(Point) returns (Feature) {}
```

- A *server-side streaming RPC* where the client sends a request to the server
  and gets a stream to read a sequence of messages back. The client reads from
  the returned stream until there are no more messages. As you can see in our
  example, you specify a server-side streaming method by placing the `stream`
  keyword before the *response* type.

```proto
// Obtains the Features available within the given Rectangle.  Results are
// streamed rather than returned at once (e.g. in a response message with a
// repeated field), as the rectangle may cover a large area and contain a
// huge number of features.
rpc ListFeatures(Rectangle) returns (stream Feature) {}
```

- A *client-side streaming RPC* where the client writes a sequence of messages
  and sends them to the server, again using a provided stream. Once the client
  has finished writing the messages, it waits for the server to read them all
  and return its response. You specify a client-side streaming method by placing
  the `stream` keyword before the *request* type.

```proto
// Accepts a stream of Points on a route being traversed, returning a
// RouteSummary when traversal is completed.
rpc RecordRoute(stream Point) returns (RouteSummary) {}
```

- A *bidirectional streaming RPC* where both sides send a sequence of messages
  using a read-write stream. The two streams operate independently, so clients
  and servers can read and write in whatever order they like: for example, the
  server could wait to receive all the client messages before writing its
  responses, or it could alternately read a message then write a message, or
  some other combination of reads and writes. The order of messages in each
  stream is preserved. You specify this type of method by placing the `stream`
  keyword before both the request and the response.

```proto
// Accepts a stream of RouteNotes sent while a route is being traversed,
// while receiving other RouteNotes (e.g. from other users).
rpc RouteChat(stream RouteNote) returns (stream RouteNote) {}
```

Our .proto file also contains protocol buffer message type definitions for all
the request and response types used in our service methods - for example, here's
the `Point` message type:

```proto
// Points are represented as latitude-longitude pairs in the E7 representation
// (degrees multiplied by 10**7 and rounded to the nearest integer).
// Latitudes should be in the range +/- 90 degrees and longitude should be in
// the range +/- 180 degrees (inclusive).
message Point {
  int32 latitude = 1;
  int32 longitude = 2;
}
```

### Generating client and server code

Next we need to generate the gRPC client and server interfaces from our .proto
service definition. We do this using the protocol buffer compiler `protoc` with
two plugins: one providing protocol buffer support for Swift (via [Swift
Protobuf][swift-protobuf]) and the other for gRPC. You need to use the
[proto3][protobuf-releases] compiler (which supports both proto2 and proto3
syntax) in order to generate gRPC services.

For simplicity, we've provided a Makefile in the `grpc-swift` directory that
runs protoc for you with the appropriate plugin, input, and output (if you want
to run this yourself, make sure you've installed protoc first):

```sh
$ make generate-route-guide
```

Running this command generates the following files in the
`Sources/Examples/RouteGuide/Model` directory:

- `route_guide.pb.swift`, which contains the implementation of your generated
    message classes
- `route_guide.grpc.swift`, which contains the implementation of your generated
    service classes

Let's look at how to run the same command manually:

```sh
$ protoc Sources/Examples/RouteGuide/Model/route_guide.proto \
    --proto_path=Sources/Examples/RouteGuide/Model \
    --plugin=./.build/debug/protoc-gen-swift \
    --swift_opt=Visibility=Public \
    --swift_out=Sources/Examples/RouteGuide/Model \
    --plugin=./.build/debug/protoc-gen-grpc-swift \
    --grpc-swift_opt=Visibility=Public \
    --grpc-swift_out=Sources/Examples/RouteGuide/Model
```

We invoke the protocol buffer compiler `protoc` with the path to our service
definition `route_guide.proto` as well as specifying the path to search for
imports. We then specify the path to the [Swift Protobuf][swift-protobuf] plugin
and any options. In our case the generated code is in a separate module to the
client and server, so the generated code must have `Public` visibility. We then
specify the directory into which the generated messages should be written. The
remainder of the arguments are very similar but pertain to the generation of the
service code and use the `protoc-gen-grpc-swift` plugin.

### Creating the server

First let's look at how we create a `RouteGuide` server. If you're only
interested in creating gRPC clients, you can skip this section and go straight
to [Creating the client](#client) (though you might find it interesting
anyway!).

There are two parts to making our `RouteGuide` service do its job:

- Implementing the service protocol generated from our service definition: doing
  the actual "work" of our service.
- Running a gRPC server to listen for requests from clients and return the
  service responses.

You can find our example `RouteGuide` provider in
[grpc-swift/Sources/Examples/RouteGuide/Server/RouteGuideProvider.swift][routeguide-provider].
Let's take a closer look at how it works.

#### Implementing RouteGuide

As you can see, our server has a `RouteGuideProvider` class that extends the
generated `Routeguide_RouteGuideProvider` protocol:

```swift
class RouteGuideProvider: Routeguide_RouteGuideProvider {
...
}
```

#### Simple RPC

`RouteGuideProvider` implements all our service methods. Let's
look at the simplest type first, `GetFeature`, which just gets a `Point` from
the client and returns the corresponding feature information from its database
in a `Feature`.

```swift
/// A simple RPC.
///
/// Obtains the feature at a given position.
///
/// A feature with an empty name is returned if there's no feature at the given position.
func getFeature(
  request point: Routeguide_Point,
  context: StatusOnlyCallContext
) -> EventLoopFuture<Routeguide_Feature> {
  return context.eventLoop.makeSucceededFuture(self.checkFeature(at: point))
}

...

/// Returns a feature at the given location or an unnamed feature if none exist at that location.
private func checkFeature(
  at location: Routeguide_Point
) -> Routeguide_Feature {
  return self.features.first(where: {
    return $0.location.latitude == location.latitude
      && $0.location.longitude == location.longitude
  }) ?? Routeguide_Feature.with {  // No feature was found: return an unnamed feature.
    $0.name = ""
    $0.location = location
  }
}
```

`getFeature()` takes two parameters:

- `Routeguide_Point`: the request
- `StatusOnlyCallContext`: a context which exposes status and trailing metadata
  fields that you can change if needed.

To return our response to the client and complete the call:

1. We construct and populate a `Routeguide_Feature` response object to return to
   the client, as specified in our service definition. In this example, we do
   this in a separate private `checkFeature()` method.
2. We return the an [`EventLoopFuture`][nio-elf] succeeded with the result from
   `checkFeature()`.

##### Server-side streaming RPC

Next let's look at one of our streaming RPCs. `ListFeatures` is a server-side
streaming RPC, so we need to send back multiple `Routeguide_Feature `s to our
client.

```swift
/// A server-to-client streaming RPC.
///
/// Obtains the Features available within the given Rectangle. Results are streamed rather than
/// returned at once (e.g. in a response message with a repeated field), as the rectangle may
/// cover a large area and contain a huge number of features.
func listFeatures(
  request: Routeguide_Rectangle,
  context: StreamingResponseCallContext<Routeguide_Feature>
) -> EventLoopFuture<GRPCStatus> {
  let left = min(request.lo.longitude, request.hi.longitude)
  let right = max(request.lo.longitude, request.hi.longitude)
  let top = max(request.lo.latitude, request.hi.latitude)
  let bottom = max(request.lo.latitude, request.hi.latitude)

  self.features.lazy.filter { feature in
    return !feature.name.isEmpty
      && feature.location.longitude >= left
      && feature.location.longitude <= right
      && feature.location.latitude >= bottom
      && feature.location.latitude <= top
  }.forEach {
    _ = context.sendResponse($0)
  }

  return context.eventLoop.makeSucceededFuture(.ok)
}
```

Like the simple RPC, this method gets a request object (the
`Routeguide_Rectangle` in which our client wants to find `Routeguide_Feature`s)
and a `StreamingResponseCallContext` context.

This time, we get as many `Routeguide_Feature` objects as we need to return to
the client (in this case, we select them from the service's feature collection
based on whether they're inside our request `Routeguide_Rectangle`), and write
them each in turn to the response observer using the contexts `sendResponse()`
method. Finally, we return a future `.ok` status to tell gRPC that we've
finished writing responses.

##### Client-side streaming RPC

Now let's look at something a little more complicated: the client-side streaming
method `RecordRoute`, where we get a stream of `Routeguide_Point`s from the client and
return a single `Routeguide_RouteSummary` with information about their trip.

```swift
/// A client-to-server streaming RPC.
///
/// Accepts a stream of Points on a route being traversed, returning a RouteSummary when traversal
/// is completed.
func recordRoute(
  context: UnaryResponseCallContext<Routeguide_RouteSummary>
) -> EventLoopFuture<(StreamEvent<Routeguide_Point>) -> Void> {
  var pointCount: Int32 = 0
  var featureCount: Int32 = 0
  var distance = 0.0
  var previousPoint: Routeguide_Point?
  let startTime = Date()

  return context.eventLoop.makeSucceededFuture({ event in
    switch event {
    case .message(let point):
      pointCount += 1
      if !self.checkFeature(at: point).name.isEmpty {
        featureCount += 1
      }

      // For each point after the first, add the incremental distance from the previous point to
      // the total distance value.
      if let previous = previousPoint {
        distance += previous.distance(to: point)
      }
      previousPoint = point

    case .end:
      let seconds = Date().timeIntervalSince(startTime)
      let summary = Routeguide_RouteSummary.with {
        $0.pointCount = pointCount
        $0.featureCount = featureCount
        $0.elapsedTime = Int32(seconds)
        $0.distance = Int32(distance)
      }
      context.responsePromise.succeed(summary)
    }
  })
}
```

As you can see our method gets a `UnaryResponseCallContext` parameter, but
this time it returns a future `StreamEvent` handler for the client to write
its `Routeguide_Point`s.

In the method body we instantiate an anonymous `StreamEvent` handler to return,
in which we:

- Get features and other information each time the client writes a
  `Routeguide_Point` to the message stream if the event is a `.message`.
- Populate and build our `Routeguide_RouteSummary` when the *client* has
  finished writing messages (the event is `.end`). We then succeed the
  response promise on the context with our `Routeguide_RouteSummary`.

##### Bidirectional streaming RPC

Finally, let's look at our bidirectional streaming RPC `RouteChat()`.

```swift
func routeChat(
  context: StreamingResponseCallContext<Routeguide_RouteNote>
) -> EventLoopFuture<(StreamEvent<Routeguide_RouteNote>) -> Void> {
  return context.eventLoop.makeSucceededFuture({ event in
    switch event {
    case .message(let note):
      // Get any notes at the location of request note.
      var notes = self.lock.withLock {
        self.notes[note.location, default: []]
      }

      // Respond with all previous notes at this location.
      for note in notes {
        _ = context.sendResponse(note)
      }

      // Add the new note and update the stored notes.
      notes.append(note)
      self.lock.withLockVoid {
        self.notes[note.location] = notes
      }

    case .end:
      context.statusPromise.succeed(.ok)
    }
  })
}
```

As with the server-side streaming RPC we accept  a `StreamingResponseCallContext`
but return a `StreamEvent` handler (like the client-side streaming RPC). The syntax
for reading and writing here is exactly the same as for our client-streaming and
server-streaming methods. Although each side will always get the other's
messages in the order they were written, both the client and server can read and
write in any order — the streams operate completely independently.

#### Starting the server

Once we've implemented all our methods, we also need to start up a gRPC server
so that clients can actually use our service. The following snippet shows how we
do this for our `RouteGuide` service:

```swift
// Create an event loop group for the server to run on.
let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
defer {
  try! group.syncShutdownGracefully()
}

// Read the feature database.
let features = try loadFeatures()

// Create a provider using the features we read.
let provider = RouteGuideProvider(features: features)

// Start the server and print its address once it has started.
let server = Server.insecure(group: group)
  .withServiceProviders([provider])
  .bind(host: "localhost", port: 0)

server.map {
  $0.channel.localAddress
}.whenSuccess { address in
  print("server started on port \(address!.port!)")
}

// Wait on the server's `onClose` future to stop the program from exiting.
_ = try server.flatMap {
  $0.onClose
}.wait()
```
As you can see, we configure and start our server using a builder.

To do this, we:

1. Create an insecure server builder; it's insecure because it does not use
   TLS.
1. Create an instance of our service implementation class `RouteGuideProvider`
   and configure the builder to use it with `withServiceProviders(_:)`,
1. Call `bind(host:port:)` on the builder with the address and port we
   want to use to listen for client requests, this starts the server.

Once the server has started succesfully we print out the port the server is
listening on. We then `wait()` on the server's `onClose` future to stop the
program from exiting (since `close()` is never called on the server).

## Creating the client

In this section, we'll look at creating a Swift client for our `RouteGuide`
service. You can see our complete example client code in
[grpc-swift/Sources/Examples/RouteGuide/Client/main.swift][routeguide-client].

#### Creating a stub

To call service methods, we first need to create a *stub*. All generated Swift
stubs are *non-blocking/asynchronous*.

First we need to create a gRPC channel for our stub, we're not using TLS so we
use the `insecure` builder and specify the server address and port we want to
connect to:

```swift
let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
defer {
  try? group.syncShutdownGracefully()
}

let channel = ClientConnection.insecure(group: group)
  .connect(host: "localhost", port: port)

let client = Routeguide_RouteGuideClient(channel: channel)
```

#### Calling service methods

Now let's look at how we call our service methods.

##### Simple RPC

Calling the simple RPC `GetFeature` is straightforward.


```swift
let point: Routeguide_Point = .with {
  $0.latitude = latitude
  $0.longitude = longitude
}

let call = client.getFeature(point)
// Block on the response future.
let feature = try call.response.wait()
```

We create and populate a request protocol buffer object (in our case
`Routeguide_Point`), pass it to the `getFeature()` method on our stub, and get back a
call object which has [`EventLoopFuture`][nio-elf]s for the initial metadata,
response (in our case a `Routeguide_Feature`), trailing metadata and call
status. We can make the call synchronous by `wait()`-ing on the response.

If an error occurs, it is encoded as a `GRPCStatus`. The status of a call is
*always* made available as the `status` on the call object.

##### Server-side streaming RPC

Next, let's look at a server-side streaming call to `ListFeatures`, which
returns a stream of geographical `Feature`s:

```swift
let rectangle: Routeguide_Rectangle = .with {
  $0.lo = .with {
    $0.latitude = numericCast(lowLatitude)
    $0.longitude = numericCast(lowLongitude)
  }
  $0.hi = .with {
    $0.latitude = numericCast(highLatitude)
    $0.longitude = numericCast(highLongitude)
  }
}

let call = client.listFeatures(rectangle) { feature in
  print("Received feature: \(feature)")
}

_ = try call.status.wait()
```

As you can see, it's very similar to the simple RPC we just looked at, except
the `call` object does not have a `response` and `listFeatures` accepts a
callback for responses. Here we `wait()` on the `status` to determine when the
call has completed.

##### Client-side streaming RPC

Now for something a little more complicated: the client-side streaming method
`RecordRoute`, where we send a stream of `Routeguide_Point`s to the server and
get back a single `Routeguide_RouteSummary`.

```swift
public func recordRoute(
  using client: Routeguide_RouteGuideServiceClient,
  features: [Routeguide_Feature],
  featuresToVisit: Int
) {
  print("→ RecordRoute")
  let options = CallOptions(timeout: .minutes(rounding: 1))
  let call = client.recordRoute(callOptions: options)

  call.response.whenSuccess { summary in
    print(
      "Finished trip with \(summary.pointCount) points. Passed \(summary.featureCount) features. " +
      "Travelled \(summary.distance) meters. It took \(summary.elapsedTime) seconds."
    )
  }

  call.response.whenFailure { error in
    print("RecordRoute Failed: \(error)")
  }

  call.status.whenComplete { _ in
    print("Finished RecordRoute")
  }

  for _ in 0..<featuresToVisit {
    let index = Int.random(in: 0..<features.count)
    let point = features[index].location
    print("Visiting point \(point.latitude), \(point.longitude)")
    call.sendMessage(point, promise: nil)

    // Sleep for a bit before sending the next one.
    Thread.sleep(forTimeInterval: TimeInterval.random(in: 0.5..<1.5))
  }

  call.sendEnd(promise: nil)

  // Wait for the call to end.
  _ = try! call.status.wait()
}
```

As you can see, the `call` object also has a `response`
[`EventLoopFuture`][nio-elf] for the `Routeguide_RouteSummary`. It also has
methods to send requests to the server.

We call `call.sendMessage` for each point we want to send to the server.
`sendMessage` has two variants, one accepting an
[`EventLoopPromise<Void>?`][nio-promise] and one returning an
[`EventLoopFuture<Void>`][nio-elf]. These values will be fulfilled when the
client has written the request to the network. In our case we don't need to know
when this is so we provide a `nil` promise.

Note that there also two `sendMessages()` methods (one accepting an
`EventLoopPromise<Void>?` and one returning an `EventLoopFuture<Void>`) for
sending multiple messages at a time,

Once we've finished writing points, we call `call.sendEnd(promise: nil)` to
tell gRPC that we've finished writing on the client side. Once we're done, we
wait on our `call.status` to check that the server has completed on its side.

##### Bidirectional streaming RPC

Finally, let's look at our bidirectional streaming RPC `RouteChat`.

```swift
func routeChat(using client: Routeguide_RouteGuideServiceClient) {
  print("→ RouteChat")

  let call = client.routeChat { note in
    print("Got message \"\(note.message)\" at \(note.location.latitude), \(note.location.longitude)")
  }

  call.status.whenSuccess { status in
    if status.code == .ok {
      print("Finished RouteChat")
    } else {
      print("RouteChat Failed: \(status)")
    }
  }

  let noteContent = [
    ("First message", 0, 0),
    ("Second message", 0, 1),
    ("Third message", 1, 0),
    ("Fourth message", 1, 1)
  ]

  for (message, latitude, longitude) in noteContent {
    let note: Routeguide_RouteNote = .with {
      $0.message = message
      $0.location = .with {
        $0.latitude = Int32(latitude)
        $0.longitude = Int32(longitude)
      }
    }

    print("Sending message \"\(note.message)\" at \(note.location.latitude), \(note.location.longitude)")
    call.sendMessage(note, promise: nil)
  }
  // Mark the end of the stream.
  call.sendEnd(promise: nil)

  // Wait for the call to end.
  _ = try! call.status.wait()
}
```

As with our client-side streaming example, we have a `call` object with methods
for sending messages to the server. We invoke our RPC with a handler for responses,
just like the server-side streaming example.

### Try it out!

Follow the instructions in the Route Guide example directory
[README][routeguide-readme] to build and run the client and server.

[grpc-docs]: https://grpc.io/docs/
[nio-elf]: https://apple.github.io/swift-nio/docs/current/NIO/Classes/EventLoopFuture.html
[nio-promise]: https://apple.github.io/swift-nio/docs/current/NIO/Structs/EventLoopPromise.html
[protobuf-docs]: https://developers.google.com/protocol-buffers/docs/proto3
[protobuf-releases]: https://github.com/google/protobuf/releases
[protocol-buffers]: https://developers.google.com/protocol-buffers/docs/overview
[routeguide-client]: ../Sources/Examples/RouteGuide/Client/main.swift
[routeguide-proto]: ../Sources/Examples/RouteGuide/Model/route_guide.proto
[routeguide-provider]: ../Sources/Examples/RouteGuide/Server/RouteGuideProvider.swift
[routeguide-readme]: ../Sources/Examples/RouteGuide/README.md
[routeguide-source]: ../Sources/Examples/RouteGuide
[swift-protobuf-guide]: https://github.com/apple/swift-protobuf/blob/master/Documentation/API.md
[swift-protobuf]: https://github.com/apple/swift-protobuf
