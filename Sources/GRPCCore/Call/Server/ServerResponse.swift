/*
 * Copyright 2023, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/// A namespace for response message types used by servers.
public enum ServerResponse {}

extension ServerResponse {
  /// A response for a single message sent by a server.
  ///
  /// Single responses are used for unary and client-streaming RPCs. For streaming responses
  /// see ``ServerResponse/Stream``.
  ///
  /// A single response captures every part of the response stream and distinguishes successful
  /// and unsuccessful responses via the ``accepted`` property. The value for the `success` case
  /// contains the initial metadata, response message, and the trailing metadata and implicitly
  /// has an ``Status/Code-swift.struct/ok`` status code.
  ///
  /// The `failure` case indicates that the server chose not to process the RPC, or the processing
  /// of the RPC failed. The failure case contains an ``RPCError`` describing why the RPC failed,
  /// including an error code, error message and any metadata sent by the server.
  ///
  /// ### Using ``Single`` responses
  ///
  /// Each response has an ``accepted`` property which contains all RPC information. You can create
  /// one by calling ``init(accepted:)`` or one of the two convenience initializers:
  /// - ``init(message:metadata:trailingMetadata:)`` to create a successful response, or
  /// - ``init(of:error:)`` to create a failed response.
  ///
  /// You can interrogate a response by inspecting the ``accepted`` property directly or by using
  /// its convenience properties:
  /// - ``metadata`` extracts the initial metadata,
  /// - ``message`` extracts the message, or throws if the response failed, and
  /// - ``trailingMetadata`` extracts the trailing metadata.
  ///
  /// The following example demonstrates how you can use the API:
  ///
  /// ```swift
  /// // Create a successful response
  /// let response = ServerResponse.Single<String>(
  ///   message: "Hello, World!",
  ///   metadata: ["hello": "initial metadata"],
  ///   trailingMetadata: ["goodbye": "trailing metadata"]
  /// )
  ///
  /// // The explicit API:
  /// switch response {
  /// case .success(let contents):
  ///   print("Received response with message '\(contents.message)'")
  /// case .failure(let error):
  ///   print("RPC failed with code '\(error.code)'")
  /// }
  ///
  /// // The convenience API:
  /// do {
  ///   print("Received response with message '\(try response.message)'")
  /// } catch let error as RPCError {
  ///   print("RPC failed with code '\(error.code)'")
  /// }
  /// ```
  public struct Single<Message: Sendable>: Sendable {
    /// An accepted RPC with a successful outcome.
    public struct Contents: Sendable {
      /// Caller-specified metadata to send to the client at the start of the response.
      ///
      /// Both gRPC Swift and its transport layer may insert additional metadata. Keys prefixed with
      /// "grpc-" are prohibited and may result in undefined behaviour. Transports may also insert
      /// their own metadata, you should avoid using key names which may clash with transport
      /// specific metadata. Note that transports may also impose limits in the amount of metadata
      /// which may be sent.
      public var metadata: Metadata

      /// The message to send to the client.
      public var message: Message

      /// Caller-specified metadata to send to the client at the end of the response.
      ///
      /// Both gRPC Swift and its transport layer may insert additional metadata. Keys prefixed with
      /// "grpc-" are prohibited and may result in undefined behaviour. Transports may also insert
      /// their own metadata, you should avoid using key names which may clash with transport
      /// specific metadata. Note that transports may also impose limits in the amount of metadata
      /// which may be sent.
      public var trailingMetadata: Metadata

      /// Create a new single client request.
      ///
      /// - Parameters:
      ///   - message: The message to send to the server.
      ///   - metadata: Metadata to send to the client at the start of the response. Defaults to
      ///       empty.
      ///   - trailingMetadata: Metadata to send to the client at the end of the response. Defaults
      ///       to empty.
      public init(
        message: Message,
        metadata: Metadata = [:],
        trailingMetadata: Metadata = [:]
      ) {
        self.metadata = metadata
        self.message = message
        self.trailingMetadata = trailingMetadata
      }
    }

    /// Whether the RPC was accepted or rejected.
    ///
    /// The `success` indicates the server accepted the RPC for processing and the RPC completed
    /// successfully and implies the RPC succeeded with the ``Status/Code-swift.struct/ok`` status
    /// code. The `failure` case indicates that the service rejected the RPC without processing it
    /// or could not process it successfully.
    public var accepted: Result<Contents, RPCError>

    /// Creates a response.
    ///
    /// - Parameter accepted: Whether the RPC was accepted or rejected.
    public init(accepted: Result<Contents, RPCError>) {
      self.accepted = accepted
    }
  }
}

extension ServerResponse {
  /// A response for a stream of messages sent by a server.
  ///
  /// Stream responses are used for server-streaming and bidirectional-streaming RPCs. For single
  /// responses see ``ServerResponse/Single``.
  ///
  /// A stream response captures every part of the response stream and distinguishes whether the
  /// request was processed by the server via the ``accepted`` property. The value for the `success`
  /// case contains the initial metadata and a closure which is provided with a message write and
  /// returns trailing metadata. If the closure returns without error then the response implicitly
  /// has an ``Status/Code-swift.struct/ok`` status code. You can throw an error from the producer
  /// to indicate that the request couldn't be handled successfully.  If an ``RPCError`` is thrown
  /// then the client will receive an equivalent error populated with the same code and message. If
  /// an error of any other type is thrown then the client will receive an error with the
  /// ``Status/Code-swift.struct/unknown`` status code.
  ///
  /// The `failure` case indicates that the server chose not to process the RPC. The failure case
  /// contains an ``RPCError`` describing why the RPC failed, including an error code, error
  /// message and any metadata to send to the client.
  ///
  /// ### Using ``Stream`` responses
  ///
  /// Each response has an ``accepted`` property which contains all RPC information. You can create
  /// one by calling ``init(accepted:)`` or one of the two convenience initializers:
  /// - ``init(of:metadata:producer:)`` to create a successful response, or
  /// - ``init(of:error:)`` to create a failed response.
  ///
  /// You can interrogate a response by inspecting the ``accepted`` property directly. The following
  /// example demonstrates how you can use the API:
  ///
  /// ```swift
  /// // Create a successful response
  /// let response = ServerResponse.Stream(
  ///   of: String.self,
  ///   metadata: ["hello": "initial metadata"]
  /// ) { writer in
  ///   // Write a few messages.
  ///   try await writer.write("Hello")
  ///   try await writer.write("World")
  ///
  ///   // Send trailing metadata to the client.
  ///   return ["goodbye": "trailing metadata"]
  /// }
  /// ```
  @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
  public struct Stream<Message: Sendable>: Sendable {
    /// The contents of a response to a request which has been accepted for processing.
    public struct Contents: Sendable {
      /// Metadata to send to the client at the beginning of the response stream.
      public var metadata: Metadata

      /// A closure which, when called, writes values into the provided writer and returns trailing
      /// metadata indicating the end of the response stream.
      ///
      /// Returning metadata indicates a successful response and gRPC will terminate the RPC with
      /// an ``Status/Code-swift.struct/ok`` status code. Throwing an error will terminate the RPC
      /// with an appropriate status code. You can control the status code, message and metadata
      /// returned to the client by throwing an ``RPCError``. If the error thrown is a type other
      /// than ``RPCError`` then a status with code ``Status/Code-swift.struct/unknown`` will
      /// be returned to the client.
      ///
      /// gRPC will invoke this function at most once therefore it isn't required to be idempotent.
      public var producer: @Sendable (RPCWriter<Message>) async throws -> Metadata

      /// Create a ``Contents``.
      ///
      /// - Parameters:
      ///   - metadata: Metadata to send to the client at the start of the response.
      ///   - producer: A function which produces values
      public init(
        metadata: Metadata,
        producer: @escaping @Sendable (RPCWriter<Message>) async throws -> Metadata
      ) {
        self.metadata = metadata
        self.producer = producer
      }
    }

    /// Whether the RPC was accepted or rejected.
    ///
    /// The `success` case indicates that the service accepted the RPC for processing and will
    /// send initial metadata back to the client before producing response messages. The RPC may
    /// still result in failure by later throwing an error.
    ///
    /// The `failure` case indicates that the server rejected the RPC and will not process it. Only
    /// the status and trailing metadata will be sent to the client.
    public var accepted: Result<Contents, RPCError>

    /// Creates a response.
    ///
    /// - Parameter accepted: Whether the RPC was accepted or rejected.
    public init(accepted: Result<Contents, RPCError>) {
      self.accepted = accepted
    }
  }
}

extension ServerResponse.Single {
  /// Creates a new accepted response.
  ///
  /// - Parameters:
  ///   - metadata: Metadata to send to the client at the beginning of the response.
  ///   - message: The response message to send to the client.
  ///   - trailingMetadata: Metadata to send to the client at the end of the response.
  public init(message: Message, metadata: Metadata = [:], trailingMetadata: Metadata = [:]) {
    let contents = Contents(
      message: message,
      metadata: metadata,
      trailingMetadata: trailingMetadata
    )
    self.accepted = .success(contents)
  }

  /// Creates a new failed response.
  ///
  /// - Parameters:
  ///   - messageType: The type of message.
  ///   - error: An error describing why the RPC failed.
  public init(of messageType: Message.Type = Message.self, error: RPCError) {
    self.accepted = .failure(error)
  }

  /// Returns the metadata to be sent to the client at the start of the response.
  ///
  /// For rejected RPCs (in other words, where ``accepted`` is `failure`) the metadata is empty.
  public var metadata: Metadata {
    switch self.accepted {
    case let .success(contents):
      return contents.metadata
    case .failure:
      return [:]
    }
  }

  /// Returns the message to send to the client.
  ///
  /// - Throws: ``RPCError`` if the request failed.
  public var message: Message {
    get throws {
      try self.accepted.map { $0.message }.get()
    }
  }

  /// Returns metadata to be sent to the client at the end of the response.
  ///
  /// Unlike ``metadata``, for rejected RPCs the metadata returned may contain values.
  public var trailingMetadata: Metadata {
    switch self.accepted {
    case let .success(contents):
      return contents.trailingMetadata
    case let .failure(error):
      return error.metadata
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerResponse.Stream {
  /// Creates a new accepted response.
  ///
  /// - Parameters:
  ///   - messageType: The type of message.
  ///   - metadata: Metadata to send to the client at the beginning of the response.
  ///   - producer: A closure which, when called, writes messages to the client.
  public init(
    of messageType: Message.Type = Message.self,
    metadata: Metadata = [:],
    producer: @escaping @Sendable (RPCWriter<Message>) async throws -> Metadata
  ) {
    let contents = Contents(metadata: metadata, producer: producer)
    self.accepted = .success(contents)
  }

  /// Creates a new failed response.
  ///
  /// - Parameters:
  ///   - messageType: The type of message.
  ///   - error: An error describing why the RPC failed.
  public init(of messageType: Message.Type = Message.self, error: RPCError) {
    self.accepted = .failure(error)
  }

  /// Returns metadata received from the server at the start of the response.
  ///
  /// For rejected RPCs (in other words, where ``accepted`` is `failure`) the metadata is empty.
  public var metadata: Metadata {
    switch self.accepted {
    case let .success(contents):
      return contents.metadata
    case .failure:
      return [:]
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerResponse.Stream {
  @_spi(Testing)
  public init(single response: ServerResponse.Single<Message>) {
    switch response.accepted {
    case .success(let contents):
      let contents = Contents(metadata: contents.metadata) {
        try await $0.write(contents.message)
        return contents.trailingMetadata
      }
      self.accepted = .success(contents)

    case .failure(let error):
      self.accepted = .failure(error)
    }
  }
}
