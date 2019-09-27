# Calling a Service Without a Generated Client

It is also possible to call gRPC services without a generated client. The models
for the requests and responses are required, however.

If you are calling a service which you don't have a generated client for, you
can use `AnyServiceClient`. For example, to call the "SayHello" RPC on the
[Greeter][helloworld-source] service you can do the following:

```swift
let connection = ... // get a ClientConnection
let anyService = AnyServiceClient(connection: connection)

let sayHello = anyService.makeUnaryCall(
  path: "/helloworld.Greeter/SayHello",
  request: Helloworld_HelloRequest.with {
    $0.name = "gRPC Swift user"
  },
  responseType: Helloworld_HelloResponse.self
)
```

Calls for client-, server- and bidirectional-streaming are done in a similar way
using `makeClientStreamingCall`, `makeServerStreamingCall`, and
`makeBidirectionalStreamingCall` respectively.

These methods are also available on generated clients, allowing you to call
methods which have been added to the service since the client was generated.

[helloworld-source]: ../Sources/Examples/HelloWorld
