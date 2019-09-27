# Apple Platforms

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

[network-framework]: https://developer.apple.com/documentation/network
[nio-ts]: https://github.com/apple/swift-nio-transport-services
