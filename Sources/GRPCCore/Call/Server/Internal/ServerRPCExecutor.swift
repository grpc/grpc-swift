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

@usableFromInline
struct ServerRPCExecutor {
  /// Executes an RPC using the provided handler.
  ///
  /// - Parameters:
  ///   - context: The context for the RPC.
  ///   - stream: The accepted stream to execute the RPC on.
  ///   - deserializer: A deserializer for messages received from the client.
  ///   - serializer: A serializer for messages to send to the client.
  ///   - interceptors: Server interceptors to apply to this RPC.
  ///   - handler: A handler which turns the request into a response.
  @inlinable
  static func execute<Input, Output>(
    context: ServerContext,
    stream: RPCStream<
      RPCAsyncSequence<RPCRequestPart, any Error>,
      RPCWriter<RPCResponsePart>.Closable
    >,
    deserializer: some MessageDeserializer<Input>,
    serializer: some MessageSerializer<Output>,
    interceptors: [ServerInterceptorTarget],
    handler: @Sendable @escaping (
      _ request: StreamingServerRequest<Input>,
      _ context: ServerContext
    ) async throws -> StreamingServerResponse<Output>
  ) async {
    // Wait for the first request part from the transport.
    let firstPart = await Self._waitForFirstRequestPart(inbound: stream.inbound)

    switch firstPart {
    case .process(let metadata, let inbound):
      await Self._execute(
        context: context,
        metadata: metadata,
        inbound: inbound,
        outbound: stream.outbound,
        deserializer: deserializer,
        serializer: serializer,
        interceptors: interceptors,
        handler: handler
      )

    case .reject(let error):
      // Stream can't be handled; write an error status and close.
      let status = Status(code: Status.Code(error.code), message: error.message)
      try? await stream.outbound.write(.status(status, error.metadata))
      await stream.outbound.finish()
    }
  }

  @inlinable
  static func _execute<Input, Output>(
    context: ServerContext,
    metadata: Metadata,
    inbound: UnsafeTransfer<RPCAsyncSequence<RPCRequestPart, any Error>.AsyncIterator>,
    outbound: RPCWriter<RPCResponsePart>.Closable,
    deserializer: some MessageDeserializer<Input>,
    serializer: some MessageSerializer<Output>,
    interceptors: [ServerInterceptorTarget],
    handler: @escaping @Sendable (
      _ request: StreamingServerRequest<Input>,
      _ context: ServerContext
    ) async throws -> StreamingServerResponse<Output>
  ) async {
    if let timeout = metadata.timeout {
      await Self._processRPCWithTimeout(
        timeout: timeout,
        context: context,
        metadata: metadata,
        inbound: inbound,
        outbound: outbound,
        deserializer: deserializer,
        serializer: serializer,
        interceptors: interceptors,
        handler: handler
      )
    } else {
      await Self._processRPC(
        context: context,
        metadata: metadata,
        inbound: inbound,
        outbound: outbound,
        deserializer: deserializer,
        serializer: serializer,
        interceptors: interceptors,
        handler: handler
      )
    }
  }

  @inlinable
  static func _processRPCWithTimeout<Input, Output>(
    timeout: Duration,
    context: ServerContext,
    metadata: Metadata,
    inbound: UnsafeTransfer<RPCAsyncSequence<RPCRequestPart, any Error>.AsyncIterator>,
    outbound: RPCWriter<RPCResponsePart>.Closable,
    deserializer: some MessageDeserializer<Input>,
    serializer: some MessageSerializer<Output>,
    interceptors: [ServerInterceptorTarget],
    handler: @escaping @Sendable (
      _ request: StreamingServerRequest<Input>,
      _ context: ServerContext
    ) async throws -> StreamingServerResponse<Output>
  ) async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        do {
          try await Task.sleep(for: timeout, clock: .continuous)
          context.cancellation.cancel()
        } catch {
          ()  // Only cancel the RPC if the timeout completes.
        }
      }

      await Self._processRPC(
        context: context,
        metadata: metadata,
        inbound: inbound,
        outbound: outbound,
        deserializer: deserializer,
        serializer: serializer,
        interceptors: interceptors,
        handler: handler
      )

      // Cancel the timeout
      group.cancelAll()
    }
  }

  @inlinable
  static func _processRPC<Input, Output>(
    context: ServerContext,
    metadata: Metadata,
    inbound: UnsafeTransfer<RPCAsyncSequence<RPCRequestPart, any Error>.AsyncIterator>,
    outbound: RPCWriter<RPCResponsePart>.Closable,
    deserializer: some MessageDeserializer<Input>,
    serializer: some MessageSerializer<Output>,
    interceptors: [ServerInterceptorTarget],
    handler: @escaping @Sendable (
      _ request: StreamingServerRequest<Input>,
      _ context: ServerContext
    ) async throws -> StreamingServerResponse<Output>
  ) async {
    let messages = UncheckedAsyncIteratorSequence(inbound.wrappedValue).map { part in
      switch part {
      case .message(let bytes):
        return try deserializer.deserialize(bytes)
      case .metadata:
        throw RPCError(
          code: .internalError,
          message: """
            Server received an extra set of metadata. Only one set of metadata may be received \
            at the start of the RPC. This is likely to be caused by a misbehaving client.
            """
        )
      }
    }

    let response = await Result {
      // Run the request through the interceptors, finally passing it to the handler.
      return try await Self._intercept(
        request: StreamingServerRequest(
          metadata: metadata,
          messages: RPCAsyncSequence(wrapping: messages)
        ),
        context: context,
        interceptors: interceptors
      ) { request, context in
        try await handler(request, context)
      }
    }.castError(to: RPCError.self) { error in
      RPCError(code: .unknown, message: "Service method threw an unknown error.", cause: error)
    }.flatMap { response in
      response.accepted
    }

    let status: Status
    let metadata: Metadata

    switch response {
    case .success(let contents):
      let result = await Result {
        // Write the metadata and run the producer.
        try await outbound.write(.metadata(contents.metadata))
        return try await contents.producer(
          .serializingToRPCResponsePart(into: outbound, with: serializer)
        )
      }.castError(to: RPCError.self) { error in
        RPCError(code: .unknown, message: "", cause: error)
      }

      switch result {
      case .success(let trailingMetadata):
        status = .ok
        metadata = trailingMetadata
      case .failure(let error):
        status = Status(code: Status.Code(error.code), message: error.message)
        metadata = error.metadata
      }

    case .failure(let error):
      status = Status(code: Status.Code(error.code), message: error.message)
      metadata = error.metadata
    }

    try? await outbound.write(.status(status, metadata))
    await outbound.finish()
  }

  @inlinable
  static func _waitForFirstRequestPart(
    inbound: RPCAsyncSequence<RPCRequestPart, any Error>
  ) async -> OnFirstRequestPart {
    var iterator = inbound.makeAsyncIterator()
    let part = await Result { try await iterator.next() }
    let onFirstRequestPart: OnFirstRequestPart

    switch part {
    case .success(.metadata(let metadata)):
      // The only valid first part.
      onFirstRequestPart = .process(metadata, UnsafeTransfer(iterator))

    case .success(.none):
      // Empty stream; reject.
      let error = RPCError(code: .internalError, message: "Empty inbound server stream.")
      onFirstRequestPart = .reject(error)

    case .success(.message):
      let error = RPCError(
        code: .internalError,
        message: """
          Invalid inbound server stream; received message bytes at start of stream. This is \
          likely to be a transport specific bug.
          """
      )
      onFirstRequestPart = .reject(error)

    case .failure(let error):
      let error = RPCError(
        code: .unknown,
        message: "Inbound server stream threw error when reading metadata.",
        cause: error
      )
      onFirstRequestPart = .reject(error)
    }

    return onFirstRequestPart
  }

  @usableFromInline
  enum OnFirstRequestPart {
    case process(
      Metadata,
      UnsafeTransfer<RPCAsyncSequence<RPCRequestPart, any Error>.AsyncIterator>
    )
    case reject(RPCError)
  }

  @usableFromInline
  enum ServerExecutorTask: Sendable {
    case timedOut(Result<Void, any Error>)
    case executed
  }
}

extension ServerRPCExecutor {
  @inlinable
  static func _intercept<Input, Output>(
    request: StreamingServerRequest<Input>,
    context: ServerContext,
    interceptors: [ServerInterceptorTarget],
    finally: @escaping @Sendable (
      _ request: StreamingServerRequest<Input>,
      _ context: ServerContext
    ) async throws -> StreamingServerResponse<Output>
  ) async throws -> StreamingServerResponse<Output> {
    return try await self._intercept(
      request: request,
      context: context,
      iterator: interceptors.makeIterator(),
      finally: finally
    )
  }

  @inlinable
  static func _intercept<Input, Output>(
    request: StreamingServerRequest<Input>,
    context: ServerContext,
    iterator: Array<ServerInterceptorTarget>.Iterator,
    finally: @escaping @Sendable (
      _ request: StreamingServerRequest<Input>,
      _ context: ServerContext
    ) async throws -> StreamingServerResponse<Output>
  ) async throws -> StreamingServerResponse<Output> {
    var iterator = iterator

    switch iterator.next() {
    case .some(let interceptorTarget):
      if interceptorTarget.applies(to: context.descriptor) {
        let iter = iterator
        do {
          return try await interceptorTarget.interceptor.intercept(
            request: request,
            context: context
          ) {
            try await self._intercept(request: $0, context: $1, iterator: iter, finally: finally)
          }
        } catch let error as RPCError {
          return StreamingServerResponse(error: error)
        } catch let other {
          let error = RPCError(code: .unknown, message: "", cause: other)
          return StreamingServerResponse(error: error)
        }
      } else {
        return try await self._intercept(
          request: request,
          context: context,
          iterator: iterator,
          finally: finally
        )
      }

    case .none:
      return try await finally(request, context)
    }
  }
}
