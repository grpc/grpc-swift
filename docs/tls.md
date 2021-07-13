# Using TLS

gRPC Swift offers two TLS 'backends'. A 'NIOSSL' backend and a 'Network.framework' backend.

The NIOSSL backend is available on Darwin and Linux and delegates to SwiftNIO SSL. The
Network.framework backend is available on recent Darwin platforms (macOS 10.14+, iOS 12+, tvOS 12+,
and watchOS 5+) and uses the TLS implementation provided by Network.framework. Moreover, the
Network.framework backend is only compatible with clients and servers using the `EventLoopGroup`
provided by SwiftNIO Transport Services, `NIOTSEventLoopGroup`.

|                             | NIOSSL backend                                       | Network.framework backend                   |
|-----------------------------|------------------------------------------------------|---------------------------------------------|
| Platform Availability       | Darwin and Linux                                     | macOS 10.14+, iOS 12+, tvOS 12+, watchOS 5+ |
| Compatible `EventLoopGroup` | `MultiThreadedEventLoopGroup`, `NIOTSEventLoopGroup` | `NIOTSEventLoopGroup`                       |

Note that on supported Darwin platforms users should the prefer using `NIOTSEventLoopGroup` and the
Network.framework backend.

## Configuring TLS

TLS may be configured in two different ways: using a client/server builder, or by constructing a
configuration object to instantiate the builder with.

### Configuring a Client

The simplest way to configure a client to use TLS is to let gRPC decide which TLS backend to use
based on the type of the provided `EventLoopGroup`:

```swift
let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
let builder = ClientConnection.usingPlatformAppropriateTLS(for: group)
```

The `builder` exposes additional methods for configuring TLS, however most methods are specific to a
backend and must not be called when that backend is not being used (the documentation for
each `withTLS(...)` method states which backend it may be applied to).

If more control is required over the configuration users may signal which backend to use and provide
an appropriate `EventLoopGroup` to one of `ClientConnection.usingTLSBackedByNIOSSL(on:)` and
`ClientConnection.usingTLSBackedByNetworkFramework(on:)`.

gRPC Swift also includes a `GRPCTLSConfiguration` object which wraps the configuration used by each
backend. An instance of this may also be provided to `ClientConnection.usingTLS(with:on:)` with an
appropriate `EventLoopGroup`.

### Configuring a Server

Servers always require some backend specific configuration, as such there is no
automatically detectable 'platform appropriate' server configuration.

To configure a server callers must pair one of
`Server.usingTLSBackedByNIOSSL(on:certificateChain:privateKey:)` and
`Server.usingTLSBackedByNetworkFramework(on:with:)` with an appropriate `EventLoopGroup` or provide
a `GRPCTLSConfiguration` and appropriate `EventLoopGroup` to `Server.usingTLS(with:on:)`.

## NIOSSL Backend: Loading Certificates and Private Keys

Using the NIOSSL backend, certificates and private keys are represented by
[`NIOSSLCertificate`][nio-ref-tlscert] and [`NIOSSLPrivateKey`][nio-ref-privatekey],
respectively.

A certificate or private key may be loaded from:
- a file using `NIOSSLCertificate(file:format:)` or `NIOSSLPrivateKey(file:format:)`, or
- an array of bytes using `NIOSSLCertificate(buffer:format:)` or `NIOSSLPrivateKey(bytes:format)`.

It is also possible to load a certificate or private key from a `String` by
constructing an array from its UTF8 view and passing it to the appropriate
initializer (`NIOSSLCertificate(buffer:format)` or
`NIOSSLPrivateKey(bytes:format:)`):

```swift
let certificateString = ...
let bytes: = Array(certificateString.utf8)

let certificateFormat = ...
let certificate = try NIOSSLCertificate(buffer: bytes, format: certificateFormat)
```

Certificate chains may also be loaded from:

- a file: `NIOSSLCertificate.fromPEMFile(_:)`, or
- an array of bytes: `NIOSSLCertificate.fromPEMBytes(_:)`.

These functions return an _array_ of certificates (`[NIOSSLCertificate]`).

Similar to loading a certificate, a certificate chain may also be loaded from
a `String` using by using the UTF8 view on the string with the
`fromPEMBytes(_:)` method.

Refer to the [certificate][nio-ref-tlscert] or [private
key][nio-ref-privatekey] documentation for more information.

[nio-ref-privatekey]: https://apple.github.io/swift-nio-ssl/docs/current/NIOSSL/Classes/NIOSSLPrivateKey.html
[nio-ref-tlscert]: https://apple.github.io/swift-nio-ssl/docs/current/NIOSSL/Classes/NIOSSLCertificate.html
[nio-ref-tlsconfig]: https://apple.github.io/swift-nio-ssl/docs/current/NIOSSL/Structs/TLSConfiguration.html
