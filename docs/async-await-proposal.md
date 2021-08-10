# Proposal: Async/await support

## Introduction

With the introduction of [async/await][SE-0296] in Swift 5.5, it is
now possible to write asynchronous code without the need for callbacks.
Language support for [`AsyncSequence`][SE-0298] also allows for writing
functions that return values over time.

We would like to explore how we could offer APIs that make use of these new
language features to allow users to implement and call gRPC services using
these new idioms.

This proposal describes what these APIs could look like and explores some of
the potential usability concerns.

## Motivation

Consider the familiar example Echo service which exposes all four types of
call: unary, client-streaming, server-streaming, and bidirectional-streaming.
It is defined as follows:

### Example Echo service

```proto
service Echo {
  // Immediately returns an echo of a request.
  rpc Get(EchoRequest) returns (EchoResponse) {}

  // Splits a request into words and returns each word in a stream of messages.
  rpc Expand(EchoRequest) returns (stream EchoResponse) {}

  // Collects a stream of messages and returns them concatenated when the caller closes.
  rpc Collect(stream EchoRequest) returns (EchoResponse) {}

  // Streams back messages as they are received in an input stream.
  rpc Update(stream EchoRequest) returns (stream EchoResponse) {}
}

message EchoRequest {
  // The text of a message to be echoed.
  string text = 1;
}

message EchoResponse {
  // The text of an echo response.
  string text = 1;
}
```

### Existing server API

To implement the Echo server, the user must implement a type that conforms to
the following generated protocol:

```swift
/// To build a server, implement a class that conforms to this protocol.
public protocol Echo_EchoProvider: CallHandlerProvider {
  var interceptors: Echo_EchoServerInterceptorFactoryProtocol? { get }

  /// Immediately returns an echo of a request.
  func get(request: Echo_EchoRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Echo_EchoResponse>

  /// Splits a request into words and returns each word in a stream of messages.
  func expand(request: Echo_EchoRequest, context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<GRPCStatus>

  /// Collects a stream of messages and returns them concatenated when the caller closes.
  func collect(context: UnaryResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void>

  /// Streams back messages as they are received in an input stream.
  func update(context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void>
}
```

### Existing example server implementation

Here is an example implementation of the bidirectional streaming handler for `update`:

```swift
public func update(
  context: StreamingResponseCallContext<Echo_EchoResponse>
) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
  var count = 0
  return context.eventLoop.makeSucceededFuture({ event in
    switch event {
    case let .message(message):
      let response = Echo_EchoResponse.with {
        $0.text = "Swift echo update (\(count)): \(message.text)"
      }
      count += 1
      context.sendResponse(response, promise: nil)

    case .end:
      context.statusPromise.succeed(.ok)
    }
  })
}
```

This API exposes a number incidental types and patterns that the user need
concern themselves with that are not specific to their application:

1. The fact that gRPC is implemented on top of NIO is not hidden from the user
   and they need to implement an API in terms of an `EventLoopFuture` and access
   an `EventLoop` from the call context.
2. There is a different context type passed to the user function for each
   different type of call and this context is generic over the response type.
3. In the server- and bidirectional-streaming call handlers, an added layer of
   asynchrony is exposed. That is, the user must return a _future_ for
   a closure that will handle incoming events.
4. The user _must_ fulfil the `statusPromise` when it receives `.end`, but there
is nothing that enforces this.

### Existing client API

Turning our attention to the client API, in order to make calls to the Echo server, the user must instantiate the generated `Echo_EchoClient` which provides the following API:

```swift
public protocol Echo_EchoClientProtocol: GRPCClient {
  var serviceName: String { get }
  var interceptors: Echo_EchoClientInterceptorFactoryProtocol? { get }

  func get(
    _ request: Echo_EchoRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Echo_EchoRequest, Echo_EchoResponse>

  func expand(
    _ request: Echo_EchoRequest,
    callOptions: CallOptions?,
    handler: @escaping (Echo_EchoResponse) -> Void
  ) -> ServerStreamingCall<Echo_EchoRequest, Echo_EchoResponse>

  func collect(
    callOptions: CallOptions?
  ) -> ClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse>

  func update(
    callOptions: CallOptions?,
    handler: @escaping (Echo_EchoResponse) -> Void
  ) -> BidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse>
}
```

### Existing example client usage

Here is an example use of the client, making a bidirectional streaming call to
`update`:

```swift
// Update is a bidirectional streaming call; provide a response handler.
let update = client.update { response in
  print("update received: \(response.text)")
}

// Send a bunch of messages to the service.
for word in ["boyle", "jeffers", "holt"] {
  let request = Echo_EchoRequest.with { $0.text = word }
  update.sendMessage(request, promise: nil)
}

// Close the request stream.
update.sendEnd(promise: nil)

// wait() for the call to terminate
let status = try update.status.wait()
print("update completed with status: \(status.code)")
```

This API also exposes a number incidental types and patterns that the user need
concern themselves with that are not specific to their application:

1. It exposes the NIO types to the user, allowing the provision of an
   `EventLoopPromise` when sending messages and requiring the use of
   `EventLoopFuture` to obtain the `status` of the call.
2. Code does not read in a straight line due to the need to provide a completion
   handler when making the call.

## Proposed solution

### Proposed server API

We propose generating the following new protocol which the user must conform to in
order to implement the server:

```swift
/// To build a server, implement a class that conforms to this protocol.
public protocol Echo_AsyncEchoProvider: CallHandlerProvider {
  var interceptors: Echo_EchoServerInterceptorFactoryProtocol? { get }

  /// Immediately returns an echo of a request.
  func get(
    request: Echo_EchoRequest,
    context: AsyncServerCallContext
  ) async throws -> Echo_EchoResponse

  /// Splits a request into words and returns each word in a stream of messages.
  func expand(
    request: Echo_EchoRequest,
    responseStreamWriter: AsyncResponseStreamWriter<Echo_EchoResponse>,
    context: AsyncServerCallContext
  ) async throws

  /// Collects a stream of messages and returns them concatenated when the caller closes.
  func collect(
    requests: GRPCAsyncStream<Echo_EchoRequest>,
    context: AsyncServerCallContext
  ) async throws -> Echo_EchoResponse

  /// Streams back messages as they are received in an input stream.
  func update(
    requests: GRPCAsyncStream<Echo_EchoRequest>,
    responseStreamWriter: AsyncResponseStreamWriter<Echo_EchoResponse>,
    context: AsyncServerCallContext
  ) async throws
}
```

Here is an example implementation of the bidirectional streaming `update`
handler using this new API:

```swift
public func update(
  requests: GRPCAsyncStream<Echo_EchoRequest>,
  responseStreamWriter: AsyncResponseStreamWriter<Echo_EchoResponse>,
  context: AsyncServerCallContext
) async throws {
  var count = 0
  for try await request in requests {
    let response = Echo_EchoResponse.with {
      $0.text = "Swift echo update (\(count)): \(request.text)"
    }
    count += 1
    try await responseStreamWriter.sendResponse(response)
  }
}
```

This API addresses the previously noted drawbacks the existing API:

> 1. The fact that gRPC is implemented on top of NIO is not hidden from the user
>   and they need to implement an API in terms of an `EventLoopFuture` and needs
>   to access an `EventLoop` from the call context.

There is no longer a need for the adopter to `import NIO` nor implement anything
in terms of NIO types. Instead they now implement an `async` function.

> 2. There is a different context type passed to the user function for each
>   different type of call and this context is generic over the response type.

The same non-generic `AsyncServerCallContext` is passed to the user function
regardless of the type of RPC.

> 3. In the server- and bidirectional-streaming call handlers, an added layer of
>   asynchrony is exposed. That is, the user must return a _future_ for
>   a closure that will handle incoming events.

The user function consumes requests from an `AsyncSequence`, using the new
language idioms.

> 4. The user _must_ fulfil the `statusPromise` when it receives `.end` but there
>   is nothing that enforces this.

The user need simply return from the function or throw an error. The closing of
the call is handled by the library.

If the user function throws a `GRPCStatus` (which already conforms to `Error`)
or a value of a type that conforms to `GRPCStatusTransformable` then the library
will take care of setting the RPC status appropriately. If the user throws
anything else then the library will still take care of setting the status
appropriately, but in this case it will use `internalError` for the RPC status.

### Proposed client API

We propose generating a client which conforms to this new protocol:

```swift
public protocol Echo_AsyncEchoClientProtocol: GRPCClient {
	var serviceName: String { get }
	var interceptors: Echo_EchoClientInterceptorFactoryProtocol? { get }

	func makeGetCall(
		_ request: Echo_EchoRequest,
		callOptions: CallOptions?
	) -> AsyncUnaryCall<Echo_EchoRequest, Echo_EchoResponse>

	func makeExpandCall(
		_ request: Echo_EchoRequest,
		callOptions: CallOptions?
	) -> AsyncServerStreamingCall<Echo_EchoRequest, Echo_EchoResponse>

	func makeCollectCall(
		callOptions: CallOptions?
	) -> AsyncClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse>

	func makeUpdateCall(
		callOptions: CallOptions?
	) -> AsyncBidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse>
}
```

Here is an example use of the new client API, making a bidirectional streaming
call to `update`:

```swift
// No longer provide a response handler when making the call.
let update = client.makeUpdateCall()

Task {
  // Send requests as before but using `await` instead of a `promise`.
  for word in ["foo", "bar", "baz"] {
    try await update.sendMessage(.with { $0.text = word })
  }
  // Close the request stream, again using `await` instead of a `promise`.
  try await update.sendEnd()
}

// Consume responses as an AsyncSequence.
for try await response in update.responseStream {
  print("update received: \(response.text)")
}

// Wait for the call to terminate, but using `await` rather than a future.
let status = await update.status
print("update completed with status: \(status.code)")
```

As highlighted in the code comments above, it allows the user to write
staight-line code, using the new async/await language support, and for
consuming responses from an `AsyncSequence` using the new `for try await ... in
{ ... }` idiom.

Specifically, this API addresses the previously noted drawbacks the existing
client API [anchor link]:

> 1. It exposes the NIO types to the user, allowing for the provision of an
>   `EventLoopPromise` when sending messages and requiring the use of
>   `EventLoopFuture` to obtain the `status` of the call.

NIO types are not exposed. Asynchronous functions and properties are marked as
`async` and the user makes use of the `await` keyword when using them.

> 2. Code does not read in a straight line due to the need to provide a completion
>   handler when making the call.

While the above example is reasonably artificial, the response handling code can
be placed after the code that is sending requests.

#### Simple/safe wrappers

The client API above provides maximum expressibility but has a notable drawback
that was not present in the existing callback-based API. Specifically, in the
server- and bidirectional-streaming cases, if the user does not consume the
responses then waiting on the status will block indefinitely. This can be
considered the converse of the drawback with the _existing_ server API that this
proposal addresses.

It is for this reason that the above proposed client APIs have slightly obscured
names (e.g. `makeUpdateCall` instead of `update`) and we propose also generating
additional, less expressive, but safer APIs. These APIs will not expose the RPC
metadata (e.g. the status, initial metadata, trailing metadata), but will
instead either simply return the response(s) or throw an error.

In addition to avoiding the pitfall of the expressive counterparts, the client-
and bidirectional-streaming calls provide the ability to pass an `AsyncSequence`
of requests. In this way, the underlying library takes care of ensuring that no
part of the RPC goes unterminated (both the request and response streams). It
also offers an opportunity for users who have an `AsyncSequence` from which they
are generating requests to make use of the combinators of `AsyncSequence` to not
have to introduce unnecessary synchrony.

We expect these will be sufficient for a lot of client use cases and, because
they do not have the same pitfalls as their more expressive counterparts, we
propose they be generated with the "plain names" of the RPC calls (e.g.
`update`).

For example, these are the additional APIs we propose to generate:

```swift
extension Echo_AsyncEchoClientProtocol {
  public func get(
    _ request: Echo_EchoRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Echo_EchoResponse { ... }

  public func collect<RequestStream>(
    requests: RequestStream,
    callOptions: CallOptions? = nil
  ) async throws -> Echo_EchoResponse
  where RequestStream: AsyncSequence, RequestStream.Element == Echo_EchoRequest { ... }

  public func expand(
    _ request: Echo_EchoRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncStream<Echo_EchoResponse> { ... }

  public func update<RequestStream>(
    requests: RequestStream,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncStream<Echo_EchoResponse>
  where RequestStream: AsyncSequence, RequestStream.Element == Echo_EchoRequest { ... }
```

Here is an example use of the safer client API, making a bidirectional streaming
call to `update` using an `AsyncSequence` of requests:

```swift
let requestStream: AsyncStream<Echo_EchoRequest> = ...  // constructed elsewhere

for try await response in client.update(requests: requestStream) {
  print("update received: \(response.text)")
}
```

Note how there is no call handler that the user needs to hold onto and use in a
safe way, they just pass in a stream of requests and consume a stream of
responses.

## Alternatives considered

### Using throwing effectful read-only properties

[Effectful read-only properties][SE-0310] were also recently added to the Swift
language. These allow for a read-only property to be marked with effects (e.g.
`async` and/or `throws`).

We considered making the status and trailing metadata properties that could
throw an error if they are awaited before the call was in the final state. The
drawback here is that you may _actually_ want to wait on the completion of the
call if for example your responses were being consumed in a concurrent task.

### Adding a throwing function to access the status

When looking at the C# implementation (which is of interest because C# also has
async/await language constructs), they provide throwing APIs to access the final
metadata for the RPC. We could consider doing the same and have not ruled it
out.

### Opaque return type for response streams

It would be nice if we didn't have to return the `GRPCAsyncStream` wrapper type
for server-streaming RPCs. Ideally we would be able to declare an opaque return
type with a constraint on its associated type. This would make the return type of
server-streaming calls more symmetric with the inputs to client-streaming calls.
For example, the bidirectional API could be defined as follows:

```swift
func update<RequestStream>(
  requests: RequestStream,
  callOptions: CallOptions? = nil
) -> some AsyncSequence where Element == Echo_EchoResponse
where RequestStream: AsyncSequence, RequestStream.Element == Echo_EchoRequest
```

Unfortunately this isn't currently supported by `AsyncSequence`, but it _has_
been called out as a [possible future enhancement][opaque-asyncsequence].

### Backpressure

This proposal makes no attempt to implement backpressure, which is also not
handled by the existing implementation.  However the API should not prevent
implementing backpressure in the future.

Since the `GRPCAsyncStream` of responses is wrapping [`AsyncStream`][SE-0314],
it may be able to offer backpressure by making use of its `init(unfolding:)`, or
`AsyncResponseStreamWriter.sendResponse(_:)` could block when the buffer is
full.

[SE-0296]: https://github.com/apple/swift-evolution/blob/main/proposals/0296-async-await.md
[SE-0298]: https://github.com/apple/swift-evolution/blob/main/proposals/0298-asyncsequence.md
[SE-0310]: https://github.com/apple/swift-evolution/blob/main/proposals/0310-effectful-readonly-properties.md
[SE-0314]: https://github.com/apple/swift-evolution/blob/main/proposals/0314-async-stream.md
[opaque-asyncsequence]: https://github.com/apple/swift-evolution/blob/0c2f85b3/proposals/0298-asyncsequence.md#opaque-types
