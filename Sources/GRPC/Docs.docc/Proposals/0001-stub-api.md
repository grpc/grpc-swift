# gRPC-0001: stub layer and interceptor API

## Overview

- Proposal: gRPC-0001
- Author(s): [George Barnett](https://github.com/glbrntt)
- Revisions:
  - v1 (25/09/23):
    - Adds type-erased wrappers for `AsyncSequence` and `Writer`.
    - Renames `BindableService` to `RPCService`
    - Add `AsyncSequence` conveneince API to `Writer`
    - Add note about possible workaround for clients returning responses

## Introduction

This proposal lays out the API design for the stub layer and interceptors for
gRPC Swift v2.

See also https://forums.swift.org/t/grpc-swift-plans-for-v2/67361.

## Motivation

The stub layer and interceptors are the highest touch point API for users of
gRPC. It's important that the API:

- Uses natural Swift idioms.
- Feels consistent between the client and server.
- Extends naturally to the interceptor API.
- Enforces the gRPC protocol by design. In other words, it should
  be impossible or difficult to construct an invalid request or response
  stream.
- Allows the gRPC protocol to fully expressed. For example, server RPC handlers
  should be able to send initial and trailing metadata when they
  choose to.

## Detailed design

This design uses the canonical "echo" service to illustrate the various call
types. The service has four methods each of which map to the four gRPC call
types:

- Get: a unary RPC,
- Collect: a client streaming RPC, and
- Expand: a server streaming RPC,
- Update: a bidirectional RPC.

The main focus of this design is the broad shape of the generated code. While
most users generate code from a service definition written in the Protocol
Buffers IDL, this design is agnostic to the source IDL.

### Request and response objects

When enumerating options and experimenting with different API, using request and
response objects emerged as the best fit. The request and response objects are
distinct between the client and the server and varied by the number of messages
they accept:

Type                       | Used by | Messages
---------------------------|---------|----------
`ClientRequest.Single<M>`  | Client  | One
`ClientRequest.Stream<M>`  | Client  | Many
`ServerRequest.Single<M>`  | Server  | One
`ServerRequest.Stream<M>`  | Server  | Many
`ClientResponse.Single<M>` | Client  | One
`ClientResponse.Stream<M>` | Client  | Many
`ServerResponse.Single<M>` | Server  | One
`ServerResponse.Stream<M>` | Server  | Many

Objects to be consumed by users are "pull based" and use `AsyncSequence`s to
represent streams of messages. Objects where messages are produced by users
(`ClientRequest.Stream` and `ServerResponse.Stream`) are "push based" and use a
"producer function" to provide messages. These types are detailed below.

```swift
public enum ClientRequest {
  /// A request created by the client containing a single message.
  public struct Single<Message: Sendable>: Sendable {
    /// Metadata sent at the begining of the RPC.
    public var metadata: Metadata

    /// The message to send to the server.
    public var message: Message

    /// Create a new single client request.
    public init(message: Message, metadata: Metadata = [:]) {
      // ...
    }
  }

  /// A request created by the client containing a message producer.
  public struct Stream<Message: Sendable>: Sendable {
    public typealias Producer = @Sendable (RPCWriter<Message>) async throws -> Void

    /// Metadata sent at the begining of the RPC.
    public var metadata: Metadata

    /// A closure which produces and writes messages into a writer destined for
    /// the server.
    ///
    /// The producer will only be consumed once by gRPC and therefore isn't
    /// required to be idempotent. If the producer throws an error then the RPC
    /// will be cancelled.
    public var producer: Producer

    /// Create a new streaming client request.
    public init(metadata: Metadata = [:], producer: @escaping Producer) {
      // ...
    }
  }
}

public enum ServerRequest {
  /// A request received at the server containing a single message.
  public struct Single<Message: Sendable>: Sendable {
    /// Metadata received from the client at the begining of the RPC.
    public var metadata: Metadata

    /// The message received from the client.
    public var message: Message

    /// Create a new single server request.
    public init(metadata: Metadata, message: Message) {
      // ...
    }
  }

  /// A request received at the server containing a stream of messages.
  public struct Stream<Message: Sendable>: Sendable {
    /// Metadata received from the client at the begining of the RPC.
    public var metadata: Metadata

    /// An `AsyncSequence` of messages received from the client.
    public var messages: RPCAsyncSequence<Message>

    /// Create a new streaming server request.
    public init(metadata: Metadata, messages: RPCAsyncSequence<Message>) {
      // ...
    }
  }
}

public enum ServerResponse {
  /// A response returned by a service for a single message.
  public struct Single<Message: Sendable>: Sendable {
    /// The outcome of the RPC.
    ///
    /// The `success` indicates the server accepted the RPC for processing and
    /// the RPC completed successfully. The `failure` case indicates that the
    /// server either rejected the RPC or threw an error while processing the
    /// request. In the `failure` case only a status and trailing metadata will
    /// be returned to the client.
    public var result: Result<Accepted, RPCError>

    /// An accepted RPC with a successful outcome.
    public struct Accepted {
      /// Metadata to send to the client at the beginning of the response stream.
      public var metadata: Metadata

      /// The single message to send back to the client.
      public var message: Message

      /// Metadata to send to the client at the end of the response stream.
      public var trailingMetadata: Metadata
    }

    public init(result: Result<Accepted, RPCError>) {
      // ...
    }

    /// Conveneince API to create an successful response.
    public init(message: Message, metadata: Metadata = [:], trailingMetadata: Metadata = [:]) {
      // ...
    }

    /// Conveneince API to create an unsuccessful response.
    public init(error: RPCError) {
      // ...
    }
  }

  /// A response returned by a service producing a stream of messages.
  public struct Stream<Message: Sendable>: Sendable {
    /// The initial outcome of the RPC; a `success` result indicates that the
    /// services has accepted the RPC for processing. The RPC may still result
    /// in failure by later throwing an error.
    ///
    /// The `failure` case indicates that the server rejected the RPC and will
    /// not process it. Only status and trailing metadata will be sent to the
    /// client.
    public var result: Result<Producer, RPCError>

    /// A closure which, when called, writes values into the provided writer and
    /// returns trailing metadata indicating the end of the response stream.
    public typealias Producer = @Sendable (RPCWriter<Message>) async throws -> Metadata

    /// An accepted RPC.
    public struct Accepted: Sendable {
      /// Metadata to send to the client at the beginning of the response stream.
      public var metadata: Metadata

      /// A closure which, when called, writes values into the provided writer and
      /// returns trailing metadata indicating the end of the response stream.
      ///
      /// Returning metadata indicates a successful response and gRPC will
      /// terminate the RPC with an 'ok' status code. Throwing an error will
      /// terminate the RPC with an appropriate status code. You can control the
      /// status code, message and metadata returned to the client by throwing an
      /// `RPCError`. If the error thrown is not an `RPCError` then the `unknown`
      /// status code is used.
      ///
      /// gRPC will invoke this function at most once therefore it isn't required
      /// to be idempotent.
      public var producer: Producer
    }

    public init(result: Result<Accepted, RPCError>) {
      // ...
    }

    /// Conveneince API to create an accepted response.
    public init(metadata: Metadata = [:], producer: @escaping Producer) {
      // ...
    }

    /// Conveneince API to create an unsuccessful response.
    public init(error: RPCError) {
      // ...
    }
  }
}

public enum ClientResponse {
  public struct Single<Message: Sendable> {
    /// The body of an accepted single response.
    public struct Body {
      /// Metadata received from the server at the start of the RPC.
      public var metadata: Metadata

      /// The message received from the server.
      public var message: Message

      /// Metadata received from the server at the end of the RPC.
      public var trailingMetadata: Metadata
    }

    /// Whether the RPC was accepted or rejected.
    ///
    /// The `success` case indicates the RPC completed successfully with an 'ok'
    /// status code. The `failure` case indicates that the RPC was rejected or
    /// couldn't be completed successfully.
    public var result: Result<Body, RPCError>

    public init(result: Result<Body, RPCError>) {
      // ...
    }

    // Note: it's possible to provide a number of conveneince APIs on top:

    /// The metadata received from server at the start of the RPC.
    ///
    /// The metadata will be empty if `result` is `failure`.
    public var metadata: Metadata {
      get {
        // ...
      }
    }

    /// The message returned from the server.
    ///
    /// Throws if the RPC was rejected or failed.
    public var message: Message {
      get throws {
        // ...
      }
    }

    /// The metadata received from server at the end of the RPC.
    public var trailingMetadata: Metadata {
      get {
        // ...
      }
    }
  }

  public struct Stream<Message: Sendable>: Sendable {
    public struct Body {
      /// Metadata received from the server at the start of the RPC.
      public var metadata: Metadata

      /// A sequence of messages received from the server ending with metadata
      /// if the RPC succeeded.
      ///
      /// If the RPC fails then the sequence will throw an error.
      public var bodyParts: RPCAsyncSequence<BodyPart>

      public enum BodyPart: Sendable {
        case message(Message)
        case trailers(Metadata)
      }
    }

    /// Whether the RPC was accepted or rejected.
    ///
    /// The `success` case indicates the RPC was accepted by the server for
    /// processing, however, the RPC may still fail by throwing an error from its
    /// `messages` sequence. The `failure` case indicates that the RPC was
    /// rejected by the server.
    public var result: Result<Body, RPCError>

    public init(result: Result<Body, RPCError>) {
      // ...
    }

    // Note: it's possible to provide a number of conveneince APIs on top:

    /// The metadata received from server at the start of the RPC.
    ///
    /// The metadata will be empty if `result` is `failure`.
    public var metadata: Metadata {
      get {
        // ...
      }
    }

    /// The stream of messages received from the server.
    public var messages: RPCAsyncSequence<Message> {
      get {
        // ...
      }
    }

    /// The metadata received from server at the end of the RPC.
    public var trailingMetadata: Metadata {
      get {
        // ...
      }
    }
  }
}

// MARK: - Supporting types

/// A sink for values which are produced over time.
public protocol Writer<Element: Sendable>: Sendable {
  /// Write a sequence of elements.
  ///
  /// Writes may suspend if the sink is unable to accept writes.
  func write(contentsOf elements: some Sequence<Element>) async throws
}

extension Writer {
  /// Write a single element.
  public func write(_ element: Element) async throws {
    try await self.write(contentsOf: CollectionOfOne(element))
  }

  /// Write an `AsyncSequence` of elements.
  public func write<Source: AsyncSequence>(
    contentsOf elements: Source
  ) async throws where Source.Element == Element {
    for try await element in elements {
      try await self.write(element)
    }
  }
}

/// A type-erasing `Writer`.
public struct RPCWriter<Element: Sendable>: Writer {
  public init<Other: Writer>(wrapping other: Other) where Other.Element == Element {
    // ...
  }
}

/// A type-erasing `AsyncSequence`.
public struct RPCAsyncSequence<Element: Sendable>: AsyncSequence, Sendable {
  public init<Other: AsyncSequence>(wrapping other: Other) where Other.Element == Element {
    // ...
  }
}

/// An RPC error.
///
/// Every RPC is terminated with a status which includes a code, and optionally,
/// a message. The status describes the ultimate outcome of the RPC.
///
/// This type is like a status but only represents negative outcomes, that is,
/// all status codes except for `ok`. This type can also carry ``Metadata``.
/// This can be used by service authors to transmit additional information to
/// clients if an RPC throws an error.
public struct RPCError: Error, Hashable, Sendable {
  public struct Code: Hashable, Sendable {
    public var code: UInt8

    private init(_ code: UInt8) {
      // ...
    }

    // All non-zero status codes from:
    // https://github.com/grpc/grpc/blob/master/doc/statuscodes.md

    /// The operation was cancelled (typically by the caller).
    public static let cancelled = Self(code: 1)

    /// Unknown error. An example of where this error may be returned is if a
    /// status value received from another address space belongs to an error-space
    /// that is not known in this address space. Also errors raised by APIs that
    /// do not return enough error information may be converted to this error.
    public static let unknown = Self(code: 2)

    // etc.
  }

  /// The error code.
  public var code: Code

  /// A message describing the error.
  public var message: String

  /// Metadata associated with the error.
  public var metadata: Metadata

  public init(code: Code, message: String, metadata: Metadata = [:]) {
    // ...
  }
}
```

### Generated server code

Code generated for each service includes two protocols. The first, higher-level
protocol which most users interact with, includes one function per defined
method. The shape of the function matches the method definition. For example
unary methods accept a `ServerRequest.Single` and return a
`ServerResponse.Single`, bidirectional streaming methods accept a
`ServerRequest.Stream` and return a `ServerResponse.Stream`.

The second, base protocol, defines each method in terms of streaming requests
and responses. The higher-level protocol refines the base protocol and provides
default implementations of methods in the base protocol in terms of their
higher-level counterpart.

The base protocol is an escape hatch allowing advanced users to have further
control over their RPCs. As an example, if a service owner needs to respond to
initial metadata in a client streaming RPC before processing the complete stream
of messages from the request they could implement their RPC in terms of the
fully streaming version provided by the base protocol.

Users can throw any error from each method. Since gRPC has a well defined error
model, gRPC Swift catches errors of type `RPCError` and extracts the code and
message. The code and message are propagated back to the client as the status of
the RPC. The library discards all other errors and returns a status with code
`unknown` to the client.

The following code demonstrates how these protocols would look for the Echo
service. Some details are elided as they aren't relevant.

```swift
// (Defined elsewhere.)
public typealias EchoRequest = ...
public typealias EchoResponse = ...

/// The generated base protocol for the "Echo" service providing each method
/// in a fully streamed form.
///
/// This protocol should typically not be implemented, instead you should
/// implement ``EchoServiceProtocol`` which refines this protocol. However, if
/// you require more granular control over your RPCs then they may implement
/// this protocol, or methods from this protocol, instead.
public protocol EchoServiceStreamingProtocol: RPCService, Sendable {
  func get(
    request: ServerRequest.Stream<EchoRequest>
  ) async throws -> ServerResponse.Stream<EchoResponse>

  func collect(
    request: ServerRequest.Stream<EchoResponse>
  ) async throws -> ServerResponse.Stream<EchoResponse>

  func expand(
    request: ServerRequest.Stream<EchoRequest>
  ) async throws -> ServerResponse.Stream<EchoResponse>

  func update(
    request: ServerRequest.Stream<EchoResponse>
  ) async throws -> ServerResponse.Stream<EchoResponse>
}

// Generated conformance to `RPCService`.
extension EchoServiceStreamingProtocol {
  public func registerRPCs(with router: inout RPCRouter) {
    // Implementation elided.
  }
}

/// The generated protocol for the "Echo" service.
///
/// You must implement an instance of this protocol with your business logic and
/// register it with a server in order to use it. See also
/// ``EchoServiceStreamingProtocol``.
public protocol EchoServiceProtocol: EchoServiceStreamingProtocol {
  func get(
    request: ServerRequest.Single<EchoRequest>
  ) async throws -> ServerResponse.Single<EchoResponse>

  func collect(
    request: ServerRequest.Stream<EchoResponse>
  ) async throws -> ServerResponse.Single<EchoResponse>

  func expand(
    request: ServerRequest.Single<EchoRequest>
  ) async throws -> ServerResponse.Stream<EchoResponse>

  func update(
    request: ServerRequest.Stream<EchoResponse>
  ) async throws -> ServerResponse.Stream<EchoResponse>
}

// Generated partial conformance to `EchoServiceStreamingProtocol`.
extension EchoServiceProtocol {
  public func get(
    request: ServerRequest.Stream<EchoRequest>
  ) async throws -> ServerResponse.Stream<EchoResponse> {
    // Implementation elided. Calls corresponding function on `EchoServiceStreamingProtocol`.
  }

  public func collect(
    request: ServerRequest.Stream<EchoResponse>
  ) async throws -> ServerResponse.Stream<EchoResponse> {
    // Implementation elided. Calls corresponding function on `EchoServiceStreamingProtocol`.
  }

  public func expand(
    request: ServerRequest.Stream<EchoRequest>
  ) async throws -> ServerResponse.Stream<EchoResponse> {
    // Implementation elided. Calls corresponding function on `EchoServiceStreamingProtocol`.
  }

  // Note: 'update' has the same definition in `EchoServiceProtocol` and
  // `EchoServiceStreamingProtocol` and is not required here.
}
```

#### Example: Echo service implementation

One could implement the Echo service as:

```swift
struct EchoService: EchoServiceProtocol {
  func get(
    request: ServerRequest.Single<EchoRequest>
  ) async throws -> ServerResponse.Single<EchoResponse> {
    // Echo back the original message.
    return ServerResponse.Single(
      message: EchoResponse(text: "echo: \(request.message.text)")
    )
  }

  func collect(
    request: ServerRequest.Stream<EchoResponse>
  ) async throws -> ServerResponse.Single<EchoResponse> {
    // Gather all request messages and join them
    let joined = try await request.messages.map {
      $0.text
    }.reduce(into: []) {
      $0.append($1)
    }.join(separator: " ")

    // Responsd with the joined message. Unlike 'get', we also echo back the
    // request metadata as the leading and trailing metadata.
    return ServerResponse.Single(
      message: EchoResponse(text: "echo: \(joined)")
      metadata: request.metadata,
      trailingMetadata: request.metadata
    )
  }

  func expand(
    request: ServerRequest.Single<EchoRequest>
  ) async throws -> ServerResponse.Stream<EchoResponse> {
    return ServerResponse.Stream { writer in
      // Echo back each part of the single request
      for part in request.message.text.split(separator: " ") {
        try await writer.write(EchoResponse(text: "echo: \(part)"))
      }

      return [:]
    }
  }

  func update(
    request: ServerRequest.Stream<EchoResponse>
  ) async throws -> ServerResponse.Stream<EchoResponse> {
    // Echo back the request metadata as the initial metadata.
    return ServerResponse.Stream(metadata: request.metadata) { writer in
      // Echo back each request message
      for try await message in request.messages {
        try await writer.write(EchoResponse(text: "echo: \(message.text)"))
      }

      // Echo back the request metadata as trailing metadata.
      return request.metadata
    }
  }
}
```

### Generated client code

The generated client code follows a similar pattern to the server code. Each
method has the same shape: it accepts a request and a closure which handles a
response from the server. The closure is generic over its return type and the
method returns that value to the caller once the closure exits. Having a
response handler provides a signal to the caller that once the closure exits the
RPC has finished and gRPC can free any related resources.

Each method also has additional parameters which the generated code would
provide defaults for, including the request encoder and response decoder.
In most cases users would not need to specify the encoder and decoder.

Code generated for the client includes a single protocol and a concrete
implementation of that protocol. The following code demonstrates how the
generated client protocol for the Echo service would look.

```swift
// (Defined elsewhere.)
public typealias EchoRequest = ...
public typealias EchoResponse = ...

/// The generated protocol for a client of the "Echo" service.
public protocol EchoClientProtocol: Sendable {
  func get<R: Sendable>(
    request: ClientRequest.Single<EchoRequest>,
    encoder: some MessageEncoder<Echo.Request>,
    decoder: some MessageDecoder<Echo.Response>,
    _ body: @Sendable @escaping (ClientResponse.Single<EchoResponse>) async throws -> R
  ) async rethrows -> R

  func collect<R: Sendable>(
    request: ClientRequest.Stream<EchoRequest>,
    encoder: some MessageEncoder<Echo.Request>,
    decoder: some MessageDecoder<Echo.Response>,
    _ body: @Sendable @escaping (ClientResponse.Single<EchoResponse>) async throws -> R
  ) async rethrows -> R

  func expand<R: Sendable>(
    request: ClientRequest.Single<EchoRequest>,
    encoder: some MessageEncoder<Echo.Request>,
    decoder: some MessageDecoder<Echo.Response>,
    _ body: @Sendable @escaping (ClientResponse.Stream<EchoResponse>) async throws -> R
  ) async rethrows -> R

  func update<R: Sendable>(
    request: ClientRequest.Stream<EchoRequest>,
    encoder: some MessageEncoder<Echo.Request>,
    decoder: some MessageDecoder<Echo.Response>,
    _ body: @Sendable @escaping (ClientResponse.Stream<EchoResponse>) async throws -> R
  ) async rethrows -> R
}

extension EchoClientProtocol {
  public func get<R: Sendable>(
    request: ClientRequest.Single<EchoRequest>,
    _ body: @Sendable @escaping (ClientResponse.Single<EchoResponse>) async throws -> R
  ) async rethrows -> R {
    // Implementation elided. Calls corresponding function on
    // `EchoClientProtocol` specifying the encoder and decoder.
  }

  func collect<R: Sendable>(
    request: ClientRequest.Stream<EchoRequest>,
    _ body: @Sendable @escaping (ClientResponse.Single<EchoResponse>) async throws -> R
  ) async rethrows -> R {
    // Implementation elided. Calls corresponding function on
    // `EchoClientProtocol` specifying the encoder and decoder.
  }

  func expand<R: Sendable>(
    request: ClientRequest.Single<EchoRequest>,
    _ body: @Sendable @escaping (ClientResponse.Stream<EchoResponse>) async throws -> R
  ) async rethrows -> R {
    // Implementation elided. Calls corresponding function on
    // `EchoClientProtocol` specifying the encoder and decoder.
  }

  func update<R: Sendable>(
    request: ClientRequest.Stream<EchoRequest>,
    _ body: @Sendable @escaping (ClientResponse.Stream<EchoResponse>) async throws -> R
  ) async rethrows -> R {
    // Implementation elided. Calls corresponding function on
    // `EchoClientProtocol` specifying the encoder and decoder.
  }
}

// Note: a concerete client implementation would also be generated. The details
// aren't interesting here.
```

#### Example: Echo client usage

An example of using the Echo client follows. Some functions highlight the
"sugared" API built on top of the more verbose lower-level API:

```swift
func get(echo: some EchoClientProtocol) async throws {
  // Make the request:
  let request = ClientRequest.Single(message: Echo.Request(text: "foo"))

  // Execute the RPC (most verbose API):
  await echo.get(request: request) { response in
    switch response.result {
    case .success(let body):
      print(
        """
        'Get' succeeded.
          metadata: \(body.metadata)
          message: \(body.message.text)
          trailing metadata: \(body.trailingMetadata)
        """
      )
    case .failure(let error):
      print("'Get' failed with error code '\(error.code)' and metadata '\(error.metadata)'")
    }
  }

  // Execute the RPC (sugared API):
  await echo.get(request: request) { response in
    print("'Get' received metadata '\(response.metadata)'")
    do {
      let message = try response.message
      print("'Get' received '\(message.text)'")
    } catch {
      print("'Get' caught error '\(error)'")
    }
  }

  // The generated code _could_ default the closure to return the response
  // message which would make the common case straighforward:
  let message = try await echo.get(request: request)
  print("'Get' received '\(message.text)'")
}

func clientStreaming(echo: some EchoClientProtocol) async throws {
  // Make the request:
  let request = ClientRequest.Stream<Echo.Request> { writer in
    for text in ["foo", "bar", "baz"] {
      try await writer.write(Echo.Request(text: text))
    }
  }

  // Execute the RPC:
  try await echo.collect(request: request) { response in
    // (Same as for the unary "Get")
  }
}

func serverStreaming(echo: some EchoClientProtocol) async throws {
  // Make the request, adding metadata:
  let request = ClientRequest.Single(
    message: Echo.Request(text: "foo bar baz"),
    metadata: ["foo": "bar"],
  )

  // Execute the RPC (most verbose API):
  try await echo.expand(request: request) { response in
    switch response.result {
    case .success(let body):
      print("'Expand' accepted with metadata '\(body.metadata)'")
      do {
        for try await part in body.bodyParts {
          switch part {
          case .message(let message):
            print("'Expand' received message '\(message.text)'")
          case .trailers(let metadata):
            print("'Expand' received trailers '\(metadata)'")
          }
        }
      } catch let error as RPCError {
        print("'Expand' failed with error '\(error.code)' and metadata '\(error.metadata)'")
      } catch {
        print("'Expand' failed with error '\(error)'")
      }
    case .failure(let error):
      print("'Expand' rejected with error '\(error.code)' and metadata '\(error.metadata)'")
    }
  }

  // Execute the RPC (sugared API):
  await echo.expand(request: request) { response in
    print("'Expand' received metadata '\(response.metadata)'")
    do {
      for try await message in response.messages {
        print("'Expand' received '\(message.text)'")
      }
    } catch let error as RPCError {
      print("'Expand' failed with error '\(error.code)' and metadata '\(error.metadata)'")
    } catch {
      print("'Expand' failed with error '\(error)'")
    }
  }

  // Note: there is no generated 'default' handler, the function body defines
  // the lifetime of the RPC and the RPC is cancelled once the closure exits.
  // Therefore escaping the message sequence would result in the sequence
  // throwing an error. It must be consumed from within the handler. It may
  // be possible for the compiler to enforce this in the future with
  // `~Escapable`.
  //
  // See: https://github.com/atrick/swift-evolution/blob/bufferview-roadmap/visions/language-support-for-BufferView.md
}

func bidirectional(echo: some EchoClient) async throws {
  // Make the request, adding metadata:
  let request = ClientRequest.Stream<Echo.Response>(metadata: ["foo": "bar"]) { writer in
    for text in ["foo", "bar", "baz"] {
      try await writer.write(Echo.Request(text: text))
    }
  }

  // Execute the RPC:
  try await echo.collect(request: request) { response in
    // (Same as for the server streaming "Expand")
  }
}
```

### Interceptors

Using the preceding patterns allows for interceptors to follow the shape of
bidirectional streaming calls. This is advantageous: once users are comfortable
with the bidirectional RPC interface the step to writing interceptors is
straighforward.

The `protocol` for client and server interceptors also have the same shape: they
require a single function `intercept` which accept a `request`, `context`, and
`next` parameters. The `request` parameter is the request object which is
_always_ the streaming variant. The `context` provides additional information
about the intercepted RPC, and `next` is a closure that the interceptor may call
to forward the request and context to the next interceptor.

```swift
/// A type that intercepts requests and response for clients.
///
/// Interceptors allow users to inspect and modify requests and responses.
/// Requests are intercepted before they are handed to a transport. Responses
/// are intercepted after they have been received from the transport and before
/// they are returned to the client.
///
/// They are typically used for cross-cutting concerns like injecting metadata,
/// validating messages, logging additional data, and tracing.
///
/// Interceptors are registered with a client and apply to all RPCs. Use the
/// ``ClientContext/descriptor`` if you need to configure behaviour on a per-RPC
/// basis.
public protocol ClientInterceptor: Sendable {
  /// Intercept a request object.
  ///
  /// - Parameters:
  ///   - request: The request object.
  ///   - context: Additional context about the request, including a descriptor
  ///       of the method being called.
  ///   - next: A closure to invoke to hand off the request and context to the next
  ///       interceptor in the chain.
  /// - Returns: A response object.
  func intercept<Input: Sendable, Output: Sendable>(
    request: ClientRequest.Stream<Input>,
    context: ClientContext,
    next: @Sendable (
      _ request: ClientRequest.Stream<Input>,
      _ context: ClientContext
    ) async throws -> ClientResponse.Stream<Output>
  ) async throws -> ClientResponse.Stream<Output>
}

/// A context passed to client interceptors containing additional information
/// about the RPC.
public struct ClientContext: Sendable {
  /// A description of the method being called including the method and service
  /// name.
  public var descriptor: MethodDescriptor
}

/// A type that intercepts requests and response for servers.
///
/// Interceptors allow users to inspect and modify requests and responses.
/// Requests are intercepted after they have been received from the transport but
/// before they have been handed off to a service. Responses are intercepted
/// after they have been returned from a service and before they are written to
/// the transport.
///
/// They are typically used for cross-cutting concerns like validating metadata
/// and messages, logging additional data, and tracing.
///
/// Interceptors are registered with the server and apply to all RPCs. Use the
/// ``ClientContext/descriptor`` if you need to configure behaviour on a per-RPC
/// basis.
public protocol ServerInterceptor: Sendable {
  /// Intercept a request object.
  ///
  /// - Parameters:
  ///   - request: The request object.
  ///   - context: Additional context about the request, including a descriptor
  ///       of the method being called.
  ///   - next: A closure to invoke to hand off the request and context to the next
  ///       interceptor in the chain.
  /// - Returns: A response object.
  func intercept<In: Sendable, Out: Sendable>(
    request: ServerRequest.Stream<In>,
    context: ServerContext,
    next: @Sendable (
      _ request: ServerRequest.Stream<In>
      _ context: ServerContext
    ) async throws -> ServerResponse.Stream<Out>
  ) async throws -> ServerResponse.Stream<Out>
}

/// A context passed to server interceptors containing additional information
/// about the RPC.
public struct ServerContext: Sendable {
  /// A description of the method being called including the method and service
  /// name.
  public var descriptor: MethodDescriptor
}
```

Importantly with this pattern, the API is a natural extension of both client and
server API for bidirectional streaming RPCs so users don't need to learn a new
paradigm, the same concepts apply.

Some examples of interceptors include:

```swift
struct AuthenticatingServerInterceptor: ServerInterceptor {
  func intercept<In: Sendable, Out: Sendable>(
    request: ServerRequest.Stream<In>,
    context: ServerContext,
    next: @Sendable (
      _ request: ServerRequest.Stream<In>
      _ context: ServerContext
    ) async throws -> ServerResponse.Stream<Out>
  ) async throws -> ServerResponse.Stream<Out> {
    guard let token = metadata["auth"], self.validate(token) else {
      // Token is missing or not valid, reject the request and respond
      // appropriately.
      return ServerResponse.Stream(
        error: RPCError(code: .unauthenticated, message: "...")
      )
    }

    // Valid token is present, forward the request.
    return try await next(request, context)
  }
}

struct LoggingClientInterceptor: ClientInterceptor {
  struct LoggingWriter<Value>: Writer {
    let base: RPCWriter<Value>

    init(wrapping base: RPCWriter<Value>) {
      self.base = base
    }

    func write(_ value: Value) async throws {
      try await self.base.write(value)
      print("Sent message: '\(value)'")
    }
  }

  func intercept<Input: Sendable, Output: Sendable>(
    request: ClientRequest.Stream<Input>,
    context: ClientContext,
    next: @Sendable (
      _ request: ClientRequest.Stream<Input>,
      _ context: ClientContext
    ) async throws -> ClientResponse.Stream<Output>
  ) async throws -> ClientResponse.Stream<Output> {
    // Construct a request which wraps the original and uses a logging writer
    // to print a message every time a message is written.
    let interceptedRequest = ClientRequest.Stream<Input>(
      metadata: request.metadata
    ) { writer in
      let loggingWriter = LoggingWriter(wrapping: writer)
      try await request.producer(loggingWriter)
      print("Send end")
    }

    print("Making request to '\(context.descriptor)', metadata: \(request.metadata)")

    let response = try await(interceptedRequest, context)
    let interceptedResponse: ClientResponse.Stream<Output>

    // Inspect the response. On success re-map the body to print each part. On
    // failure print the error.
    switch response.result {
    case .success(let body):
      print("Call accepted, metadata: '\(body.metadata)'")
      interceptedResponse = ClientResponse.Stream(
        result = .success(
          ClientResponse.Stream.Body(
            metadata: body.metadata,
            bodyParts: body.bodyParts.map {
              switch $0 {
              case .message(let message):
                print("Received message: '\(message)'")
              case .metadata(let metadata):
                print("Received metadata: '\(metadata)'")
              }

              return $0
            }
          )
        )
      )

    case .failure(let error):
      print("Call failed with error code: '\(error.code)', metadata: '\(error.metadata)'")
      interceptedResponse = response
    }

    return interceptedResponse
  }
}
```

## Alternative approaches

When enumerating designs there were a number of alternatives considered which
were ultimately dismissed. These are briefly described in the following
sections.

### Strong error typing

As gRPC has well defined error codes, having API which enforce `RPCError` as
the thrown error type is appealing as it ensures service authors propagate
appropriate information to clients and clients know they can only observe
`RPCError`s.

However, Swift doesn't currently have typed throws so would have to resort to
using `Result` types. While the API could be heavily sugared it doesn't result in
idiomatic code. There are a few places where using `Result` types simply doesn't
work in an ergonomic way. Each `AsyncSequence`, for example, would have to be
non-throwing and use `Result` types as their `Element`.

> Note: there has been recent active work in this area for Embedded Swift so
> this might be worth revisiting in the future.
>
> https://forums.swift.org/t/status-check-typed-throws/66637

### Using `~Copyable` writers

One appealing aspect of `~Copyable` types and ownership modifiers is that it's
easy to represent an writer as a kind of state machine. Consider a writer passed
to a server handler, for example. Initially it may either send metadata or it
may return a status as its first and only value. If it writes metadata it may
then write messages. After any number of messages it may then write a final
status. This composes naturally with `~Copyable` types:

```swift
struct Writer<Message>: ~Copyable {
  consuming func writeMetadata(_ metadata: Metadata) async throws -> Body {
    // ...
  }

  consuming func writeEnd(_ metadata: Metadata) async throws {
    // ...
  }

  struct Body: ~Copyable {
    func writeMessage(_ message: Message) async throws {
      // ...
    }

    consuming func writeEnd(_ metadata: Metadata) async throws {
      // ...
    }
  }
}
```

This neatly encapsulates the stream semantics of gRPC and uses the compiler to
ensure that writing an invalid stream is impossible. However, in practice it isn't
ergonomic to use as it requires dealing with multiple writer types and users can
still reach for writer functions after consuming the type, they just result in
an error. It also doesn't obviously allow for "default" values, the API forces users
to send initial metadata to get the `Body` writer. In practice most users don't
need to set metadata and the framework sends empty metadata on their behalf.

### Using `AsyncSequence` for outbound message streams

The `ClientRequest.Stream` and `ServerResponse.Stream` each have a `producer`
closure provided by callers. This is a "push" based system: callers must emit
messages into the writer when they wish to send messages to the other peer.

An alternative to this would be to use a "pull" based API like `AsyncSequence`.
There are, however, some downsides to this.

The first is that many `AsyncSequence` implementations don't appropriately exert
backpressure to the producer: `AsyncStream`, for example has an unbounded buffer
by default, this is problematic as the underlying transport may not be able to
consume messages as fast as the sequence is producing them. `AsyncChannel` has a
maximum buffer size of 1, while this wouldn't overwhelm the transport, it has
undesirable performance characteristics requiring expensive suspension points
for each message. The `Writer` approach allows the transport to directly exert
backpressure on the writer.

Finally, on the server, to allow users to send trailing metadata, the
caller would have to deal with an `enum` of messages and metadata. The onus
would fall on the implementer of the service to ensure that metadata only
appears once as the final element in the stream. The proposed
`ServerResponse.Stream` avoids this by requiring the user to specify a closure
which accepts a writer and returns `Metadata`. This ensures implementers can
send any number of messages followed by exactly one `Metadata`.

### Clients returning responses

The proposed client API requires that the caller consumes responses within a
closure. A more obvious spelling is for the client methods to return a response
object to the caller.

However, this has a number of issues. For example it doesn't make the lifetime
of the RPC obvious to the caller which can result in users accidentally keeping
expensive network resources alive for longer than necessary. Another issue is
that RPCs typically have deadlines associated with them which are naturally
modelled as separate `Task`s. These `Task`s need to run somewhere, which isn't
possible to do without resorting to unstructured concurrency. Using a response
handler allows the client to run the RPC within a `TaskGroup` and have the
response handler run as a child task next to any tasks which require running
concurrently.

One workaround is for clients to have a long running `TaskGroup` for executing
such tasks required by RPCs. This would allow a model whereby the request is
intercepted in the callers task (and would therefore also have access to task
local values) and then be transferred to the clients long running task for
execution. In this model the lifetime of the RPC would be bounded by the
lifetime of the response object. One major downside to this approach is that
task locals are only reachable from the interceptors: they wouldn't be reachable
from the transport layer which may have its own transport-specific interceptors.
