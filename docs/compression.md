# Compression

gRPC Swift supports compression.

### How to enable compression for the Client

You can configure compression via the messageEncoding property on CallOptions:

```swift
// Configure encoding
let encodingConfiguration = ClientMessageEncoding.Configuration(
  forRequests: .gzip, // use gzip for requests
  acceptableForResponses: .all, // accept all supported algorithms for responses
  decompressionLimit: .ratio(20) // reject messages and fail the RPC if a response decompresses to over 20x its compressed size
)

// Enable compression with configuration
let options = CallOptions(messageEncoding: .enabled(encodingConfiguration))

// Use the options to make a request
let rpc = echo.get(request, callOptions: options)
// ...
```