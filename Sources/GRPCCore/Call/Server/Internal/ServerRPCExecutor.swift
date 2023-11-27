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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@usableFromInline
struct ServerRPCExecutor {
  /// Executes an RPC using the provided handler.
  ///
  /// - Parameters:
  ///   - stream: The accepted stream to execute the RPC on.
  ///   - deserializer: A deserializer for messages received from the client.
  ///   - serializer: A serializer for messages to send to the client.
  ///   - interceptors: Server interceptors to apply to this RPC.
  ///   - handler: A handler which turns the request into a response.
  @inlinable
  static func execute<Input, Output>(
    stream: RPCStream<RPCAsyncSequence<RPCRequestPart>, RPCWriter<RPCResponsePart>.Closable>,
    deserializer: some MessageDeserializer<Input>,
    serializer: some MessageSerializer<Output>,
    interceptors: [any ServerInterceptor],
    handler: @Sendable @escaping (
      _ request: ServerRequest.Stream<Input>
    ) async throws -> ServerResponse.Stream<Output>
  ) async {
    // Wait for the first request part from the transport.
    let firstPart = await Self._waitForFirstRequestPart(inbound: stream.inbound)

    switch firstPart {
    case .process(let metadata, let inbound):
      await Self._execute(
        method: stream.descriptor,
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
      stream.outbound.finish()
    }
  }

  @inlinable
  static func _execute<Input, Output>(
    method: MethodDescriptor,
    metadata: Metadata,
    inbound: UnsafeTransfer<RPCAsyncSequence<RPCRequestPart>.AsyncIterator>,
    outbound: RPCWriter<RPCResponsePart>.Closable,
    deserializer: some MessageDeserializer<Input>,
    serializer: some MessageSerializer<Output>,
    interceptors: [any ServerInterceptor],
    handler: @escaping @Sendable (
      _ request: ServerRequest.Stream<Input>
    ) async throws -> ServerResponse.Stream<Output>
  ) async {
    await withTaskGroup(of: ServerExecutorTask.self) { group in
      if let timeout = metadata.timeout {
        group.addTask {
          let result = await Result {
            try await Task.sleep(for: timeout, clock: .continuous)
          }
          return .timedOut(result)
        }
      }

      group.addTask {
        await Self._processRPC(
          method: method,
          metadata: metadata,
          inbound: inbound,
          outbound: outbound,
          deserializer: deserializer,
          serializer: serializer,
          interceptors: interceptors,
          handler: handler
        )
        return .executed
      }

      while let next = await group.next() {
        switch next {
        case .timedOut(.success):
          // Timeout expired; cancel the work.
          group.cancelAll()

        case .timedOut(.failure):
          // Timeout failed (because it was cancelled). Wait for more tasks to finish.
          ()

        case .executed:
          // The work finished. Cancel any remaining tasks.
          group.cancelAll()
        }
      }
    }
  }

  @inlinable
  static func _processRPC<Input, Output>(
    method: MethodDescriptor,
    metadata: Metadata,
    inbound: UnsafeTransfer<RPCAsyncSequence<RPCRequestPart>.AsyncIterator>,
    outbound: RPCWriter<RPCResponsePart>.Closable,
    deserializer: some MessageDeserializer<Input>,
    serializer: some MessageSerializer<Output>,
    interceptors: [any ServerInterceptor],
    handler: @escaping @Sendable (
      ServerRequest.Stream<Input>
    ) async throws -> ServerResponse.Stream<Output>
  ) async {
    let messages = AsyncIteratorSequence(inbound.wrappedValue).map { part throws -> Input in
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
        request: ServerRequest.Stream(
          metadata: metadata,
          messages: RPCAsyncSequence(wrapping: messages)
        ),
        context: ServerInterceptorContext(descriptor: method),
        interceptors: interceptors
      ) { request, _ in
        try await handler(request)
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
    outbound.finish()
  }

  @inlinable
  static func _waitForFirstRequestPart(
    inbound: RPCAsyncSequence<RPCRequestPart>
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
    case process(Metadata, UnsafeTransfer<RPCAsyncSequence<RPCRequestPart>.AsyncIterator>)
    case reject(RPCError)
  }

  @usableFromInline
  enum ServerExecutorTask {
    case timedOut(Result<Void, Error>)
    case executed
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ServerRPCExecutor {
  @inlinable
  static func _intercept<Input, Output>(
    request: ServerRequest.Stream<Input>,
    context: ServerInterceptorContext,
    interceptors: [any ServerInterceptor],
    finally: @escaping @Sendable (
      _ request: ServerRequest.Stream<Input>,
      _ context: ServerInterceptorContext
    ) async throws -> ServerResponse.Stream<Output>
  ) async throws -> ServerResponse.Stream<Output> {
    return try await self._intercept(
      request: request,
      context: context,
      iterator: interceptors.makeIterator(),
      finally: finally
    )
  }

  @inlinable
  static func _intercept<Input, Output>(
    request: ServerRequest.Stream<Input>,
    context: ServerInterceptorContext,
    iterator: Array<any ServerInterceptor>.Iterator,
    finally: @escaping @Sendable (
      _ request: ServerRequest.Stream<Input>,
      _ context: ServerInterceptorContext
    ) async throws -> ServerResponse.Stream<Output>
  ) async throws -> ServerResponse.Stream<Output> {
    var iterator = iterator

    switch iterator.next() {
    case .some(let interceptor):
      let iter = iterator
      do {
        return try await interceptor.intercept(request: request, context: context) {
          try await self._intercept(request: $0, context: $1, iterator: iter, finally: finally)
        }
      } catch let error as RPCError {
        return ServerResponse.Stream(error: error)
      } catch let other {
        let error = RPCError(code: .unknown, message: "", cause: other)
        return ServerResponse.Stream(error: error)
      }

    case .none:
      return try await finally(request, context)
    }
  }
}
