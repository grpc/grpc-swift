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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
internal enum ClientStreamExecutor {
  /// Execute a request on the stream executor.
  ///
  /// - Parameters:
  ///   - request: A streaming request.
  ///   - method: A description of the method to call.
  ///   - context: The client context.
  ///   - attempt: The attempt number for the RPC that will be executed.
  ///   - serializer: A request serializer.
  ///   - deserializer: A response deserializer.
  ///   - stream: The stream to excecute the RPC on.
  /// - Returns: A streamed response.
  @inlinable
  static func execute<Input: Sendable, Output: Sendable>(
    in group: inout TaskGroup<Void>,
    request: StreamingClientRequest<Input>,
    context: ClientContext,
    attempt: Int,
    serializer: some MessageSerializer<Input>,
    deserializer: some MessageDeserializer<Output>,
    stream: RPCStream<ClientTransport.Inbound, ClientTransport.Outbound>
  ) async -> StreamingClientResponse<Output> {
    // Let the server know this is a retry.
    var metadata = request.metadata
    if attempt > 1 {
      metadata.previousRPCAttempts = attempt &- 1
    }

    group.addTask {
      await Self._processRequest(on: stream.outbound, request: request, serializer: serializer)
    }

    let part = await Self._waitForFirstResponsePart(on: stream.inbound)
    // Wait for the first response to determine how to handle the response.
    switch part {
    case .metadata(var metadata, let iterator):
      // Attach the number of previous attempts, it can be useful information for callers.
      if attempt > 1 {
        metadata.previousRPCAttempts = attempt &- 1
      }

      let bodyParts = RawBodyPartToMessageSequence(
        base: UncheckedAsyncIteratorSequence(iterator.wrappedValue),
        deserializer: deserializer
      )

      // Expected happy case: the server is processing the request.
      return StreamingClientResponse(
        metadata: metadata,
        bodyParts: RPCAsyncSequence(wrapping: bodyParts)
      )

    case .status(let status, var metadata):
      // Attach the number of previous attempts, it can be useful information for callers.
      if attempt > 1 {
        metadata.previousRPCAttempts = attempt &- 1
      }

      // Expected unhappy (but okay) case; the server rejected the request.
      return StreamingClientResponse(status: status, metadata: metadata)

    case .failed(let error):
      // Very unhappy case: the server did something unexpected.
      return StreamingClientResponse(error: error)
    }
  }

  @inlinable  // would be private
  static func _processRequest<Outbound>(
    on stream: some ClosableRPCWriterProtocol<RPCRequestPart>,
    request: StreamingClientRequest<Outbound>,
    serializer: some MessageSerializer<Outbound>
  ) async {
    let result = await Result {
      try await stream.write(.metadata(request.metadata))
      try await request.producer(.map(into: stream) { .message(try serializer.serialize($0)) })
    }.castError(to: RPCError.self) { other in
      RPCError(code: .unknown, message: "Write failed.", cause: other)
    }

    switch result {
    case .success:
      await stream.finish()
    case .failure(let error):
      await stream.finish(throwing: error)
    }
  }

  @usableFromInline
  enum OnFirstResponsePart: Sendable {
    case metadata(Metadata, UnsafeTransfer<ClientTransport.Inbound.AsyncIterator>)
    case status(Status, Metadata)
    case failed(RPCError)
  }

  @inlinable  // would be private
  static func _waitForFirstResponsePart(
    on stream: ClientTransport.Inbound
  ) async -> OnFirstResponsePart {
    var iterator = stream.makeAsyncIterator()
    let result = await Result<OnFirstResponsePart, any Error> {
      switch try await iterator.next() {
      case .metadata(let metadata):
        return .metadata(metadata, UnsafeTransfer(iterator))

      case .status(let status, let metadata):
        return .status(status, metadata)

      case .message:
        let error = RPCError(
          code: .internalError,
          message: """
            Invalid stream. The transport returned a message as the first element in the \
            stream, expected metadata. This is likely to be a transport-specific bug.
            """
        )
        return .failed(error)

      case .none:
        if Task.isCancelled {
          throw CancellationError()
        } else {
          let error = RPCError(
            code: .internalError,
            message: """
              Invalid stream. The transport returned an empty stream. This is likely to be \
              a transport-specific bug.
              """
          )
          return .failed(error)
        }
      }
    }.castError(to: RPCError.self) { error in
      RPCError(
        code: .unknown,
        message: "The transport threw an unexpected error.",
        cause: error
      )
    }

    switch result {
    case .success(let firstPart):
      return firstPart
    case .failure(let error):
      return .failed(error)
    }
  }

  @usableFromInline
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  struct RawBodyPartToMessageSequence<
    Base: AsyncSequence<RPCResponsePart, Failure>,
    Message: Sendable,
    Deserializer: MessageDeserializer<Message>,
    Failure: Error
  >: AsyncSequence, Sendable where Base: Sendable {
    @usableFromInline
    typealias Element = AsyncIterator.Element

    @usableFromInline
    let base: Base
    @usableFromInline
    let deserializer: Deserializer

    @inlinable
    init(base: Base, deserializer: Deserializer) {
      self.base = base
      self.deserializer = deserializer
    }

    @inlinable
    func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(base: self.base.makeAsyncIterator(), deserializer: self.deserializer)
    }

    @usableFromInline
    struct AsyncIterator: AsyncIteratorProtocol {
      @usableFromInline
      typealias Element = StreamingClientResponse<Message>.Contents.BodyPart

      @usableFromInline
      var base: Base.AsyncIterator
      @usableFromInline
      let deserializer: Deserializer

      @inlinable
      init(base: Base.AsyncIterator, deserializer: Deserializer) {
        self.base = base
        self.deserializer = deserializer
      }

      @inlinable
      mutating func next(
        isolation actor: isolated (any Actor)?
      ) async throws(any Error) -> StreamingClientResponse<Message>.Contents.BodyPart? {
        guard let part = try await self.base.next(isolation: `actor`) else { return nil }

        switch part {
        case .metadata(let metadata):
          let error = RPCError(
            code: .internalError,
            message: """
              Received multiple sets of metadata from the transport. This is likely to be a \
              transport specific bug. Metadata received: '\(metadata)'.
              """
          )
          throw error

        case .message(let bytes):
          let message = try self.deserializer.deserialize(bytes)
          return .message(message)

        case .status(let status, let metadata):
          if let error = RPCError(status: status, metadata: metadata) {
            throw error
          } else {
            return .trailingMetadata(metadata)
          }
        }
      }

      @inlinable
      mutating func next() async throws -> StreamingClientResponse<Message>.Contents.BodyPart? {
        try await self.next(isolation: nil)
      }
    }
  }
}
