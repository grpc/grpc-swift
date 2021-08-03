# Apple Platforms

NIO offers extensions to provide first-class support for Apple platforms (iOS
12+, macOS 10.14+, tvOS 12+, watchOS 6+) via [NIO Transport Services][nio-ts].
NIO Transport Services uses [Network.framework][network-framework] and
`DispatchQueue`s to schedule tasks.

To use NIO Transport Services in gRPC Swift you need to provide a
`NIOTSEventLoopGroup` to the builder for your client or server.
gRPC Swift provides a helper method to provide the correct `EventLoopGroup`
based on the network preference:

```swift
PlatformSupport.makeEventLoopGroup(loopCount:networkPreference:) -> EventLoopGroup
```

Here `networkPreference` defaults to `.best`, which chooses the
`.networkFramework` implementation if it is available (iOS 12+, macOS 10.14+,
tvOS 12+, watchOS 6+) and uses `.posix` otherwise.

Note that the TLS implementation used by gRPC depends on the type of `EventLoopGroup`
provided to the client or server and that some combinations are not supported.
See the [TLS docs][docs-tls] for more.

[network-framework]: https://developer.apple.com/documentation/network
[nio-ts]: https://github.com/apple/swift-nio-transport-services
[docs-tls]: ./tls.md
