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

[nio-ref-tlsconfig]: https://apple.github.io/swift-nio-ssl/docs/current/NIOSSL/Structs/TLSConfiguration.html
