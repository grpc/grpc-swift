# Using TLS

gRPC calls can be made over a secure channel by configuring TLS. This requires
specifying `tls` on `ClientConnection.Configuration` or
`Server.Configuration`.

For the client, `tls` can be as simple as:

```swift
let tls = ClientConnection.Configuration.TLS()
```

For the server, `tls` is slightly more complicated as it requires a certificate
chain and private key:

```swift
# Load the certificates from "cert.pem"
let certificates: [NIOSSLCertificate] = try NIOSSLCertificate.fromPEMFile("cert.pem")

let tls = Server.Configuration.TLS(
  certificateChain: certificates.map { .certificate($0) },
  privateKey: .file("key.pem")
)
```

The `TLS` configuration is a subset of [`TLSConfiguration`][nio-ref-tlsconfig]
provided by `NIOSSL` to ensure it meets the gRPC specification. Users may also
initialize `TLS` with `TLSConfiguration` should they require.

## Loading Certificates and Private Keys

Certificate and private key objects ([`NIOSSLCertificate`][nio-ref-tlscert] and
[`NIOSSLPrivateKey`][nio-ref-privatekey]) are provided by SwiftNIO SSL.

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

Simillar to loading a certificate, a certificate chain may also be loaded from
a `String` using by using the UTF8 view on the string with the
`fromPEMBytes(_:)` method.

Refer to the [certificate][nio-ref-tlscert] or [private
key][nio-ref-privatekey] documentation for more information.

[nio-ref-privatekey]: https://apple.github.io/swift-nio-ssl/docs/current/NIOSSL/Classes/NIOSSLPrivateKey.html
[nio-ref-tlscert]: https://apple.github.io/swift-nio-ssl/docs/current/NIOSSL/Classes/NIOSSLCertificate.html
[nio-ref-tlsconfig]: https://apple.github.io/swift-nio-ssl/docs/current/NIOSSL/Structs/TLSConfiguration.html
