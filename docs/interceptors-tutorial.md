# Interceptors Tutorial

This tutorial provides an introduction to interceptors in gRPC Swift. It assumes
you are familiar with gRPC Swift (if you aren't, try the
[quick-start guide][quick-start] or [basic tutorial][basic-tutorial] first).

### What are Interceptors?

Interceptors are a mechanism which allows users to, as the name suggests,
intercept the request and response streams of RPCs. They may be used on the
client and the server, and any number of interceptors may be used for a single
RPC. They are often used to provide cross-cutting functionality such as logging,
metrics, and authentication.

### Interceptor API

Interceptors are created by implementing a subclass of `ClientInterceptor` or
`ServerInterceptor` depending on which peer the interceptor is intended for.
Each type is interceptor base class is generic over the request and response
type for the RPC: `ClientInterceptor<Request, Response>` and
`ServerInterceptor<Request, Response>`.

The API for the client and server interceptors are broadly similar (with
differences in the message types on the stream). Each offer
`send(_:promise:context:)` and `receive(_:context:)` functions where the
provided `context` (`ClientInterceptorContext<Request, Response>` and
`ServerInterceptorContext<Request, Response>` respectively) exposes methods for
calling the next interceptor once the message part has been handled.

Each `context` type also provides the `EventLoop` that the RPC is being invoked
on and some additional information, such as the type of the RPC (unary,
client-streaming, etc.) the path (e.g. "/echo.Echo/Get"), and a logger.

### Defining an interceptor

This tutorial builds on top of the [Echo example][echo-example].

As described above, interceptors are created by subclassing `ClientInterceptor`
or `ServerInterceptor`. For the sake of brevity we will only cover creating our
own `ClientInterceptor` which prints events as they happen.

First we create our interceptor class, for the Echo service all RPCs have the
same request and response type so we'll use these types concretely here. An
interceptor may of course remain generic over the request and response types.

```swift
class LoggingEchoClientInterceptor: ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse> {
  // ...
}
```

Note that the default behavior of every interceptor method is a no-op; it will
just pass the unmodified part to the next interceptor by invoking the
appropriate method on the context.

Let's look at intercepting the request stream by overriding `send`:

```swift
override func send(
  _ part: GRPCClientRequestPart<Echo_EchoRequest>,
  promise: EventLoopPromise<Void>?,
  context: ClientInterceptorContext<Echo_EchoRequest, Echo_EchoResponse>
) {
  // ...
}
```

`send` is called with a request part generic over the request type for the RPC
(for a sever interceptor this would be a response part generic over the response
type), an optional `EventLoopPromise<Void>` promise which will be completed when
the request has been written to the network, and a `ClientInterceptorContext`.

The `GRPCClientRequestPart<Request>` `enum` has three cases:
- `metadata(HPACKHeaders)`: the user-provided request headers which are sent at
  the start of each RPC. The headers will be augmented with transport and
  protocol specific headers once the request part reaches the transport.
- `message(Request, MessageMetadata)`: a request message and associated metadata
  (such as whether the message should be compressed and whether to flush the
  transport after writing the message). For unary and server-streaming RPCs we
  expect exactly one message, for client-streaming and bidirectional-streaming
  RPCs any number of messages (including zero) is permitted.
- `end`: the end of the request stream which must be sent exactly once as the
  final part on the stream, after which no more request parts may be sent.

Below demonstrates how one could log information about a request stream using an
interceptor, after which we use the `context` to forward the request part and
promise to the next interceptor:

```swift
class LoggingEchoClientInterceptor: ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse> {
  override func send(
    _ part: GRPCClientRequestPart<Echo_EchoRequest>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Echo_EchoRequest, Echo_EchoResponse>
  ) {
    switch part {
    case let .metadata(headers):
      print("> Starting '\(context.path)' RPC, headers: \(headers)")

    case let .message(request, _):
      print("> Sending request with text '\(request.text)'")

    case .end:
      print("> Closing request stream")
    }

    // Forward the request part to the next interceptor.
    context.send(part, promise: promise)
  }

  // ...
}
```

Now let's look at the response stream by intercepting `receive`:

```swift
override func receive(
  _ part: GRPCClientResponsePart<Echo_EchoResponse>,
  context: ClientInterceptorContext<Echo_EchoRequest, Echo_EchoResponse>
) {
  // ...
}
```

`receive` is called with a response part generic over the response type for the
RPC and the same `ClientInterceptorContext` as used in `send`. The response
parts are also similar:

The `GRPCClientResponsePart<Response>` `enum` has three cases:
- `metadata(HPACKHeaders)`: the response headers returned from the server. We
  expect these at the start of a response stream, however it is also valid to
  see no `metadata` parts on the response stream if the server fails the RPC
  immediately (in which case we will just see the `end` part).
- `message(Response)`: a response message received from the server. For unary
  and client-streaming RPCs at most one message is expected (but not required).
  For server-streaming and bidirectional-streaming any number of messages
  (including zero) is permitted.
- `end(GRPCStatus, HPACKHeaders)`: the end of the response stream (and by
  extension, request stream) containing the RPC status (why the RPC ended) and
  any trailers returned by the server. We expect one `end` part per RPC, after
  which no more response parts may be received and no more request parts will be
  sent.

The code for receiving is similar to that for sending:

```swift
class LoggingEchoClientInterceptor: ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse> {
  // ...

  override func receive(
    _ part: GRPCClientResponsePart<Echo_EchoResponse>,
    context: ClientInterceptorContext<Echo_EchoRequest, Echo_EchoResponse>
  ) {
    switch part {
    case let .metadata(headers):
      print("< Received headers: \(headers)")

    case let .message(response):
      print("< Received response with text '\(response.text)'")

    case let .end(status, trailers):
      print("< Response stream closed with status: '\(status)' and trailers: \(trailers)")
    }

    // Forward the response part to the next interceptor.
    context.receive(part)
  }
}
```

In this example the implementations of `send` and `receive` directly forward the
request and response parts to the next interceptor. This is not a requirement:
implementations are free to drop, delay or redirect parts as necessary,
`context.send(_:promise:)` may be called in `receive(_:context:)` and
`context.receive(_:)` may be called in `send(_:promise:context:)`. A server
interceptor which validates an authorization header, for example, may
immediately send back an `end` when receiving request headers lacking a valid
authorization header.

### Using interceptors

Interceptors are provided to a generated client or service provider via an
implementation of generated factory protocol. For our echo example this will be
`Echo_EchoClientInterceptorFactoryProtocol` for the client and
`Echo_EchoServerInterceptorFactoryProtocol` for the server.

Each protocol has one method per RPC which returns an array of
appropriately typed interceptors to use when intercepting that RPC. Factory
methods are called at the start of each RPC.

It's important to note the order in which the interceptors are called. For the
client the array of interceptors should be in 'outbound' order, that is, when
sending a request part the _first_ interceptor to be called is the first in the
array. When the client receives a response part from the server the _last_
interceptor in the array will receive that part first.

For server factories the order is reversed: when receiving a request part the
_first_ interceptor in the array will be called first, when sending a response
part the _last_ interceptor in the array will be called first.

Implementing a factory is straightforward, in our case the Echo service has four
RPCs, all of which return the `LoggingEchoClientInterceptor` we defined above.

```
class ExampleClientInterceptorFactory: Echo_EchoClientInterceptorFactoryProtocol {
  // Returns an array of interceptors to use for the 'Get' RPC.
  func makeGetInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [LoggingEchoClientInterceptor()]
  }

  // Returns an array of interceptors to use for the 'Expand' RPC.
  func makeExpandInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [LoggingEchoClientInterceptor()]
  }

  // Returns an array of interceptors to use for the 'Collect' RPC.
  func makeCollectInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [LoggingEchoClientInterceptor()]
  }

  // Returns an array of interceptors to use for the 'Update' RPC.
  func makeUpdateInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [LoggingEchoClientInterceptor()]
  }
}
```

An interceptor factory may be passed to the generated client on initialization:

```swift
let echo = Echo_EchoClient(channel: channel, interceptors: ExampleClientInterceptorFactory())
```

For the server, providing an (optional) interceptor factory is a requirement
of the generated service provider protocol and is left to the implementation of
the provider:

```swift
protocol Echo_EchoProvider: CallHandlerProvider {
  var interceptors: Echo_EchoServerInterceptorFactoryProtocol? { get }

  // ...
}
```

### Running the example

The code listed above is available in the [Echo example][echo-example]. To run
it, from the root of your gRPC-Swift checkout start the Echo server on a free
port by running:

```
$ swift run Echo server 0
starting insecure server
started server: [IPv6]::1/::1:51274
```

Note the port that your server started on. In another terminal run the client
without the interceptors with:

```
$ swift run Echo client <PORT> get "Hello"
get receieved: Swift echo get: Hello
get completed with status: ok (0)
```

This calls the unary "Get" RPC and prints the response and status from the RPC.
Let's run it with our interceptor enabled by adding the `--intercept` flag:

```
$ swift run Echo client --intercept <PORT> get "Hello"
> Starting '/echo.Echo/Get' RPC, headers: []
> Sending request with text 'Hello'
> Closing request stream
< Received headers: [':status': '200', 'content-type': 'application/grpc']
< Received response with text 'Swift echo get: Hello'
get receieved: Swift echo get: Hello
< Response stream closed with status: 'ok (0): OK' and trailers: ['grpc-status': '0', 'grpc-message': 'OK']
get completed with status: ok (0)
```

Now we see the output from the logging interceptor: we invoke an RPC to
'Get' on the 'echo.Echo' service followed by the request with the text we
provided and the end of the request stream. Then we see response parts from the
server, the headers at the start of the response stream: a 200-OK status and the
gRPC content-type header, followed by the response and the end of response
stream and trailers.

### A note on thread safety

It is important to note that interceptor functions are invoked on the
`EventLoop` provided by the context and that implementations *must* respect this
by invoking methods on the `context` from that `EventLoop`.

[quick-start]: ../quick-start.md
[basic-tutorial]: ../basic-tutorial.md
[echo-example]: ../Sources/Examples/Echo
