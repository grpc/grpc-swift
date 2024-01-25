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

/// A namespace for response message types used by clients.
public enum ClientResponse {}

extension ClientResponse {
  /// A response for a single message received by a client.
  ///
  /// Single responses are used for unary and client-streaming RPCs. For streaming responses
  /// see ``ClientResponse/Stream``.
  ///
  /// A single response captures every part of the response stream and distinguishes successful
  /// and unsuccessful responses via the ``accepted`` property. The value for the `success` case
  /// contains the initial metadata, response message, and the trailing metadata and implicitly
  /// has an ``Status/Code-swift.struct/ok`` status code.
  ///
  /// The `failure` case indicates that the server chose not to process the RPC, or the processing
  /// of the RPC failed, or the client failed to execute the request. The failure case contains
  /// an ``RPCError`` describing why the RPC failed, including an error code, error message and any
  /// metadata sent by the server.
  ///
  /// ### Using ``Single`` responses
  ///
  /// Each response has a ``accepted`` property which contains all RPC information. You can create
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
  /// let response = ClientResponse.Single<String>(
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
    /// The contents of an accepted response with a single message.
    public struct Contents: Sendable {
      /// Metadata received from the server at the beginning of the response.
      ///
      /// The metadata may contain transport-specific information in addition to any application
      /// level metadata provided by the service.
      public var metadata: Metadata

      /// The response message received from the server.
      public var message: Message

      /// Metadata received from the server at the end of the response.
      ///
      /// The metadata may contain transport-specific information in addition to any application
      /// level metadata provided by the service.
      public var trailingMetadata: Metadata

      /// Creates a `Contents`.
      ///
      /// - Parameters:
      ///   - metadata: Metadata received from the server at the beginning of the response.
      ///   - message: The response message received from the server.
      ///   - trailingMetadata: Metadata received from the server at the end of the response.
      public init(
        metadata: Metadata,
        message: Message,
        trailingMetadata: Metadata
      ) {
        self.metadata = metadata
        self.message = message
        self.trailingMetadata = trailingMetadata
      }
    }

    /// Whether the RPC was accepted or rejected.
    ///
    /// The `success` case indicates the RPC completed successfully with an
    /// ``Status/Code-swift.struct/ok`` status code. The `failure` case indicates that the RPC was
    /// rejected by the server and wasn't processed or couldn't be processed successfully.
    public var accepted: Result<Contents, RPCError>

    /// Creates a new response.
    ///
    /// - Parameter accepted: The result of the RPC.
    public init(accepted: Result<Contents, RPCError>) {
      self.accepted = accepted
    }
  }
}

extension ClientResponse {
  /// A response for a stream of messages received by a client.
  ///
  /// Stream responses are used for server-streaming and bidirectional-streaming RPCs. For single
  /// responses see ``ClientResponse/Single``.
  ///
  /// A stream response captures every part of the response stream over time and distinguishes
  /// accepted and rejected requests via the ``accepted`` property. An "accepted" request is one
  /// where the the server responds with initial metadata and attempts to process the request. A
  /// "rejected" request is one where the server responds with a status as the first and only
  /// response part and doesn't process the request body.
  ///
  /// The value for the `success` case contains the initial metadata and a ``RPCAsyncSequence`` of
  /// message parts (messages followed by a single status). If the sequence completes without
  /// throwing then the response implicitly has an ``Status/Code-swift.struct/ok`` status code.
  /// However, the response sequence may also throw an ``RPCError`` if the server fails to complete
  /// processing the request.
  ///
  /// The `failure` case indicates that the server chose not to process the RPC or the client failed
  /// to execute the request. The failure case contains an ``RPCError`` describing why the RPC
  /// failed, including an error code, error message and any metadata sent by the server.
  ///
  /// ### Using ``Stream`` responses
  ///
  /// Each response has a ``accepted`` property which contains RPC information. You can create
  /// one by calling ``init(accepted:)`` or one of the two convenience initializers:
  /// - ``init(of:metadata:bodyParts:)`` to create an accepted response, or
  /// - ``init(of:error:)`` to create a failed response.
  ///
  /// You can interrogate a response by inspecting the ``accepted`` property directly or by using
  /// its convenience properties:
  /// - ``metadata`` extracts the initial metadata,
  /// - ``messages`` extracts the sequence of response message, or throws if the response failed.
  ///
  /// The following example demonstrates how you can use the API:
  ///
  /// ```swift
  /// // Create a failed response
  /// let response = ClientResponse.Stream(
  ///   of: String.self,
  ///   error: RPCError(code: .notFound, message: "The requested resource couldn't be located")
  /// )
  ///
  /// // The explicit API:
  /// switch response {
  /// case .success(let contents):
  ///   for try await part in contents.bodyParts {
  ///     switch part {
  ///     case .message(let message):
  ///       print("Received message '\(message)'")
  ///     case .trailingMetadata(let metadata):
  ///       print("Received trailing metadata '\(metadata)'")
  ///     }
  ///   }
  /// case .failure(let error):
  ///   print("RPC failed with code '\(error.code)'")
  /// }
  ///
  /// // The convenience API:
  /// do {
  ///   for try await message in response.messages {
  ///     print("Received message '\(message)'")
  ///   }
  /// } catch let error as RPCError {
  ///   print("RPC failed with code '\(error.code)'")
  /// }
  /// ```
  @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
  public struct Stream<Message: Sendable>: Sendable {
    public struct Contents: Sendable {
      /// Metadata received from the server at the beginning of the response.
      ///
      /// The metadata may contain transport-specific information in addition to any application
      /// level metadata provided by the service.
      public var metadata: Metadata

      /// A sequence of stream parts received from the server ending with metadata if the RPC
      /// succeeded.
      ///
      /// If the RPC fails then the sequence will throw an ``RPCError``.
      ///
      /// The sequence may only be iterated once.
      public var bodyParts: RPCAsyncSequence<BodyPart>

      /// Parts received from the server.
      public enum BodyPart: Sendable {
        /// A response message.
        case message(Message)
        /// Metadata. Must be the final value of the sequence unless the stream throws an error.
        case trailingMetadata(Metadata)
      }

      /// Creates a ``Contents``.
      ///
      /// - Parameters:
      ///   - metadata: Metadata received from the server at the beginning of the response.
      ///   - bodyParts: An `AsyncSequence` of parts received from the server.
      public init(
        metadata: Metadata,
        bodyParts: RPCAsyncSequence<BodyPart>
      ) {
        self.metadata = metadata
        self.bodyParts = bodyParts
      }
    }

    /// Whether the RPC was accepted or rejected.
    ///
    /// The `success` case indicates the RPC was accepted by the server for
    /// processing, however, the RPC may still fail by throwing an error from its
    /// `messages` sequence. The `failure` case indicates that the RPC was
    /// rejected by the server.
    public var accepted: Result<Contents, RPCError>

    /// Creates a new response.
    ///
    /// - Parameter accepted: The result of the RPC.
    public init(accepted: Result<Contents, RPCError>) {
      self.accepted = accepted
    }
  }
}

// MARK: - Convenience API

extension ClientResponse.Single {
  /// Creates a new accepted response.
  ///
  /// - Parameters:
  ///   - metadata: Metadata received from the server at the beginning of the response.
  ///   - message: The response message received from the server.
  ///   - trailingMetadata: Metadata received from the server at the end of the response.
  public init(message: Message, metadata: Metadata = [:], trailingMetadata: Metadata = [:]) {
    let contents = Contents(
      metadata: metadata,
      message: message,
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

  /// Returns the message received from the server.
  ///
  /// - Throws: ``RPCError`` if the request failed.
  public var message: Message {
    get throws {
      try self.accepted.map { $0.message }.get()
    }
  }

  /// Returns metadata received from the server at the end of the response.
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
extension ClientResponse.Stream {
  /// Creates a new accepted response.
  ///
  /// - Parameters:
  ///   - messageType: The type of message.
  ///   - metadata: Metadata received from the server at the beginning of the response.
  ///   - bodyParts: An ``RPCAsyncSequence`` of response parts received from the server.
  public init(
    of messageType: Message.Type = Message.self,
    metadata: Metadata,
    bodyParts: RPCAsyncSequence<Contents.BodyPart>
  ) {
    let contents = Contents(metadata: metadata, bodyParts: bodyParts)
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

  /// Returns metadata received from the server at the end of the response.
  ///
  /// Unlike ``metadata``, for rejected RPCs the metadata returned may contain values.
  public var messages: RPCAsyncSequence<Message> {
    switch self.accepted {
    case let .success(contents):
      let filtered = contents.bodyParts.compactMap {
        switch $0 {
        case let .message(message):
          return message
        case .trailingMetadata:
          return nil
        }
      }

      return RPCAsyncSequence(wrapping: filtered)

    case let .failure(error):
      return RPCAsyncSequence.throwing(error)
    }
  }
}
