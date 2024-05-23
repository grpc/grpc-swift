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
running the following command (replacing `x.y.z` with the latest release, for
example `1.7.0`):

```sh
$ git clone -b x.y.z https://github.com/grpc/grpc-swift
```

Then change your current directory to `grpc-swift/Sources/Examples/RouteGuide`:

```sh
$ cd grpc-swift/Sources/Examples/RouteGuide
```


### Defining the service

Our first step (as you'll know from the [Overview][grpc-docs]) is to
define the gRPC *service* and the method *request* and *response* types using
[protocol buffers][protocol-buffers]. You can see the complete .proto file in
[`grpc-swift/Protos/examples/route_guide/route_guide.proto`][routeguide-proto].

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

For simplicity, we've provided a shell script ([grpc-swift/Protos/generate.sh][run-protoc]) that
runs protoc for you with the appropriate plugin, input, and output (if you want
to run this yourself, make sure you've installed protoc first):

```sh
$ Protos/generate.sh
```

Running this command generates the following files in the
`Sources/Examples/RouteGuide/Model` directory:

- `route_guide.pb.swift`, which contains the implementation of your generated
    message classes
- `route_guide.grpc.swift`, which contains the implementation of your generated
    service classes

Let's look at how to run the same command manually:

```sh
$ protoc Protos/examples/route_guide/route_guide.proto \
    --proto_path=Protos/examples/route_guide \
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
client and server, so the generated code must have `Public` visibility. We also
specified that the 'async' client and server should be generated. The 'async'
versions use Swift concurrency features introduced in Swift 5.5. We then
specify the directory into which the generated messages should be written. The
remainder of the arguments are very similar but pertain to the generation of the
service code and use the `protoc-gen-grpc-swift` plugin.

### Creating the server

First let's look at how we create a `RouteGuide` server. If you're only
interested in creating gRPC clients, you can skip this section and go straight
to [Creating the client](#creating-the-client) (though you might find it interesting
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
generated `Routeguide_RouteGuideAsyncProvider` protocol:

```swift
final class RouteGuideProvider: Routeguide_RouteGuideAsyncProvider {
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
  context: GRPCAsyncServerCallContext
) async throws -> Routeguide_Feature {
  return self.lookupFeature(at: point) ?? Routeguide_Feature.with {
    // No feature was found: return an unnamed feature.
    $0.name = ""
    $0.location = location
  }
}

/// Returns a feature at the given location or an unnamed feature if none exist at that location.
private func lookupFeature(
  at location: Routeguide_Point
) -> Routeguide_Feature? {
  return self.features.first(where: {
    return $0.location.latitude == location.latitude
      && $0.location.longitude == location.longitude
  })
}
```

`getFeature(request:context:)` takes two parameters:

- `Routeguide_Point`: the request
- `GRPCAsyncServerCallContext`: a context which exposes various pieces of
  information about the call.

To return our response to the client and complete the call:

1. We construct and populate a `Routeguide_Feature` response object to return to
   the client, as specified in our service definition. In this example, we do
   this in a separate private `lookupFeature(at:)` method.
2. We return the feature returned from `lookupFeature(at:)` or an unnamed one if
   there was no feature at the given location.

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
  responseStream: GRPCAsyncResponseStreamWriter<Routeguide_Feature>,
  context: GRPCAsyncServerCallContext
) async throws {
  let longitudeRange = request.lo.longitude ... request.hi.longitude
  let latitudeRange = request.lo.latitude ... request.hi.latitude

  for feature in self.features where !feature.name.isEmpty {
    if feature.location.isWithin(latitude: latitudeRange, longitude: longitudeRange) {
      try await responseStream.send(feature)
    }
  }
}
```

Like the simple RPC, this method gets a request object (the
`Routeguide_Rectangle` in which our client wants to find `Routeguide_Feature`s),
a stream to write responses on and a context.

This time, we get as many `Routeguide_Feature` objects as we need to return to
the client (in this case, we select them from the service's feature collection
based on whether they're inside our request `Routeguide_Rectangle`), and write
them each in turn to the response stream using `send(_:)` method on
`responseStream`.

##### Client-side streaming RPC

Now let's look at something a little more complicated: the client-side streaming
method `RecordRoute`, where we get a stream of `Routeguide_Point`s from the client and
return a single `Routeguide_RouteSummary` with information about their trip.

```swift
/// A client-to-server streaming RPC.
///
/// Accepts a stream of Points on a route being traversed, returning a RouteSummary when traversal
/// is completed.
internal func recordRoute(
  requestStream points: GRPCAsyncRequestStream<Routeguide_Point>,
  context: GRPCAsyncServerCallContext
) async throws -> Routeguide_RouteSummary {
  var pointCount: Int32 = 0
  var featureCount: Int32 = 0
  var distance = 0.0
  var previousPoint: Routeguide_Point?
  let startTimeNanos = DispatchTime.now().uptimeNanoseconds

  for try await point in points {
    pointCount += 1

    if let feature = self.lookupFeature(at: point), !feature.name.isEmpty {
      featureCount += 1
    }

    if let previous = previousPoint {
      distance += previous.distance(to: point)
    }

    previousPoint = point
  }

  let durationInNanos = DispatchTime.now().uptimeNanoseconds - startTimeNanos
  let durationInSeconds = Double(durationInNanos) / 1e9

  return .with {
    $0.pointCount = pointCount
    $0.featureCount = featureCount
    $0.elapsedTime = Int32(durationInSeconds)
    $0.distance = Int32(distance)
  }
}
```

As you can see our method gets a `GRPCAsyncServerCallContext` parameter and a
request stream of points and returns a summary.

In the method body we iterate over the asynchronous stream of points send by the
client. For each point we:

- Check if there is a feature at that point.
- Calculate the distance between the point and the last point we saw.

After the *client* has finished sending points we populate and return a
`Routeguide_RouteSummary`.

##### Bidirectional streaming RPC

Finally, let's look at our bidirectional streaming RPC `routeChat()`.

```swift
func routeChat(
  requestStream: GRPCAsyncRequestStream<Routeguide_RouteNote>,
  responseStream: GRPCAsyncResponseStreamWriter<Routeguide_RouteNote>,
  context: GRPCAsyncServerCallContext
) async throws {
  for try await note in requestStream {
    let existingNotes = await self.notes.addNote(note, to: note.location)

    // Respond with all existing notes.
    for existingNote in existingNotes {
      try await responseStream.send(existingNote)
    }
  }
}

final actor Notes {
  private var recordedNotes: [Routeguide_Point: [Routeguide_RouteNote]] = [:]

  /// Record a note at the given location and return the all notes which were previously recorded
  /// at the location.
  func addNote(
    _ note: Routeguide_RouteNote,
    to location: Routeguide_Point
  ) -> ArraySlice<Routeguide_RouteNote> {
    self.recordedNotes[location, default: []].append(note)
    return self.recordedNotes[location]!.dropLast(1)
  }
}
```

Here we receive a request stream of `Routeguide_RouteNote`s and a response
stream of `Routeguide_RouteNote`s as well as the `GRPCAsyncServerCallContext`
we got in other RPCs.

For the route chat for iterate over the stream of notes sent by the *client* and
for each note we add it to a `Notes` helper `actor`. When a note is added to
the `Notes` `actor` all notes previously recorded at the same location are
returned and are sent back to the client.

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
[grpc-swift/Sources/Examples/RouteGuide/Client/RouteGuideClient.swift][routeguide-client].

#### Creating a stub

To call service methods, we first need to create a *stub*. All generated Swift
stubs are *non-blocking/asynchronous*.

First we need to create a gRPC channel for our stub, we're not using TLS so we
use the `.plaintext` security transport and specify the server address and port
we want to connect to:

```swift
let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
defer {
  try? group.syncShutdownGracefully()
}

let channel = try GRPCChannelPool.with(
  target: .host("localhost", port: port),
  transportSecurity: .plaintext,
  eventLoopGroup: group
)

let routeGuide = Routeguide_RouteGuideAsyncClient(channel: channel)
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

let feature = try await routeGuide.getFeature(point)
```

We create and populate a request protocol buffer object (in our case
`Routeguide_Point`), pass it to the `getFeature()` method on our stub, and
`await` the response `Routeguide_Feature`.

If an error occurs, it is encoded as a `GRPCStatus` and thrown whilst
`await`-ing the response.

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

for try await feature in routeGuide.listFeatures(rectangle) {
  print("Received feature: \(feature)")
}
```

As you can see, it's very similar to the simple RPC we just looked at, except
the `listFeatures(_:)` returns a stream of responses. Here we `await` each
response on the stream, once we finish iterating the response stream the call is
complete.

##### Client-side streaming RPC

Now for something a little more complicated: the client-side streaming method
`RecordRoute`, where we send a stream of `Routeguide_Point`s to the server and
get back a single `Routeguide_RouteSummary`.

```swift
let recordRoute = routeGuide.makeRecordRouteCall()

for _ in 1 ... featuresToVisit {
  if let feature = features.randomElement() {
    let point = feature.location
    try await recordRoute.requestStream.send(point)
  }
}

try await recordRoute.requestStream.finish()
let summary = try await recordRoute.response
```

Here we we create a record route call. It has a request stream and a single
`await`-able response for the `Routeguide_RouteSummary`.

We call `recordRoute.requestStream.send(_:)` for each point we want to send to the
server and `await` for the call to accept the request.

Once we've finished writing points, we call `recordRoute.requestStream.finish()`
to tell gRPC that we've finished writing on the client side. Once we're done, we
`await` on the `recordRoute.summary` to check that the server responded with.

##### Bidirectional streaming RPC

Finally, let's look at our bidirectional streaming RPC `RouteChat`.

```swift
let notes: [Routeguide_RouteNote] = ...

try await withThrowingTaskGroup(of: Void.self) { group in
  let routeChat = self.routeGuide.makeRouteChatCall()

  group.addTask {
    for note in notes {
      try await routeChat.requestStream.send(note)
    }
    try await routeChat.requestStream.finish()
  }

  group.addTask {
    for try await note in routeChat.responseStream {
      print("Received message '\(note.message)' at \(note.location)")
    }
  }

  try await group.waitForAll()
}
```

As with our client-side streaming example, we have a `routeChat` call object
with a `requestStream` but a `responseStream` instead of a single `await`-able
response. In this example we create a task group and create separate tasks for
sending requests and receiving responses and await for both to complete.

### Try it out!

Follow the instructions in the Route Guide example directory
[README][routeguide-readme] to build and run the client and server.

[grpc-docs]: https://grpc.io/docs/
[protobuf-docs]: https://developers.google.com/protocol-buffers/docs/proto3
[protobuf-releases]: https://github.com/google/protobuf/releases
[protocol-buffers]: https://developers.google.com/protocol-buffers/docs/overview
[routeguide-client]: ../Sources/Examples/RouteGuide/Client/RouteGuideClient.swift
[routeguide-proto]: ../Protos/examples/route_guide/route_guide.proto
[routeguide-provider]: ../Sources/Examples/RouteGuide/Server/RouteGuideProvider.swift
[routeguide-readme]: ../Sources/Examples/RouteGuide/README.md
[routeguide-source]: ../Sources/Examples/RouteGuide
[run-protoc]: ../Protos/generate.sh
[swift-protobuf-guide]: https://github.com/apple/swift-protobuf/blob/main/Documentation/API.md
[swift-protobuf]: https://github.com/apple/swift-protobuf
