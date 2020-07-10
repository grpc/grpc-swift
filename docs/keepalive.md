# Keepalive

gRPC sends HTTP2 pings on the transport to detect if the connection is down.
If the ping is not acknowledged by the other side within a certain period, the connection
will be closed. Note that pings are only necessary when there is no activity on the connection. 

## What should I set?

It should be sufficient for most users to only change `interval` and `timeout` properties, but the 
following properties can also be useful in certain use cases.

Property | Client | Server | Description
---------|--------|--------|------------
interval|Int64.max (disabled)|.hours(2)|The amount of time to wait before sending a keepalive ping.
timeout|.seconds(20)|.seconds(20)|The amount of time to wait for an acknowledgment. This value must be less than `interval`.
permitWithoutCalls|false|false|Send keepalive pings even if there are no calls in flight.
maximumPingsWithoutData|2|2|Maximum number of pings that can be sent when there is no data/header frame to be sent/
minimumSentPingIntervalWithoutData|.minutes(5)|.minutes(5)|If there are no data/header frames being received: the minimum amount of time to wait between successive pings.
minimumReceivedPingIntervalWithoutData|N/A|.minutes(5)|If there are no data/header frames being sent: the minimum amount of time expected between receiving successive pings. If the time between successive pings is less than this value, then the ping will be considered a bad ping from the peer. Such a ping counts as a "ping strike".
maximumPingStrikes|N/A|2|Maximum number of bad pings that the server will tolerate before sending an HTTP2 GOAWAY frame and closing the connection. Setting it to `0` allows the server to accept any number of bad pings.

### Client 

```swift
let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

let keepalive = ClientConnectionKeepalive(
  interval: .seconds(15),
  timeout: .seconds(10)
)

let configuration = ClientConnection.Configuration(
  target: .hostAndPort("localhost", 443),
  eventLoopGroup: group,
  connectionKeepalive: keepalive
)

let client = ClientConnection(configuration: configuration)
```

### Server

```swift
let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

let keepalive = ServerConnectionKeepalive(
  interval: .seconds(15),
  timeout: .seconds(10)
)

let configuration = Server.Configuration(
  target: .hostAndPort("localhost", 443),
  eventLoopGroup: group,
  connectionKeepalive: keepalive,
  serviceProviders: [YourCallHandlerProvider()]
)

let server = Server.makeBootstrap(configuration: configuration)
```

Fore more information, please visit the [gRPC Core documentation for keepalive](https://github.com/grpc/grpc/blob/master/doc/keepalive.md)
