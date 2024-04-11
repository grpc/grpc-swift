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
enum ClientRPCExecutor {
  /// Execute the request and handle its response.
  ///
  /// - Parameters:
  ///   - request: The request to execute.
  ///   - method: A description of the method to execute the request against.
  ///   - configuration: The execution configuration.
  ///   - serializer: A serializer to convert input messages to bytes.
  ///   - deserializer: A deserializer to convert bytes to output messages.
  ///   - transport: The transport to execute the request on.
  ///   - interceptors: An array of interceptors which the request and response pass through. The
  ///       interceptors will be called in the order of the array.
  ///   - handler: A closure for handling the response. Once the closure returns, any resources from
  ///       the RPC will be torn down.
  /// - Returns: The result returns from the `handler`.
  @inlinable
  static func execute<Input: Sendable, Output: Sendable, Result: Sendable>(
    request: ClientRequest.Stream<Input>,
    method: MethodDescriptor,
    options: CallOptions,
    serializer: some MessageSerializer<Input>,
    deserializer: some MessageDeserializer<Output>,
    transport: some ClientTransport,
    interceptors: [any ClientInterceptor],
    handler: @Sendable @escaping (ClientResponse.Stream<Output>) async throws -> Result
  ) async throws -> Result {
    switch options.executionPolicy?.wrapped {
    case .none:
      let oneShotExecutor = OneShotExecutor(
        transport: transport,
        timeout: options.timeout,
        interceptors: interceptors,
        serializer: serializer,
        deserializer: deserializer
      )

      return try await oneShotExecutor.execute(
        request: request,
        method: method,
        options: options,
        responseHandler: handler
      )

    case .retry(let policy):
      let retryExecutor = RetryExecutor(
        transport: transport,
        policy: policy,
        timeout: options.timeout,
        interceptors: interceptors,
        serializer: serializer,
        deserializer: deserializer,
        bufferSize: 64  // TODO: the client should have some control over this.
      )

      return try await retryExecutor.execute(
        request: request,
        method: method,
        options: options,
        responseHandler: handler
      )

    case .hedge(let policy):
      let hedging = HedgingExecutor(
        transport: transport,
        policy: policy,
        timeout: options.timeout,
        interceptors: interceptors,
        serializer: serializer,
        deserializer: deserializer,
        bufferSize: 64  // TODO: the client should have some control over this.
      )

      return try await hedging.execute(
        request: request,
        method: method,
        options: options,
        responseHandler: handler
      )
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ClientRPCExecutor {
  /// Executes a request on a given stream processor.
  ///
  /// - Warning: This method is "unsafe" because the `streamProcessor` must be running in a task
  ///   while this function is executing.
  ///
  /// - Parameters:
  ///   - request: The request to execute.
  ///   - method: A description of the method to execute the request against.
  ///   - attempt: The attempt number of the request.
  ///   - serializer: A serializer to convert input messages to bytes.
  ///   - deserializer: A deserializer to convert bytes to output messages.
  ///   - interceptors: An array of interceptors which the request and response pass through. The
  ///       interceptors will be called in the order of the array.
  ///   - streamProcessor: A processor which executes the serialized request.
  /// - Returns: The deserialized response.
  @inlinable
  static func unsafeExecute<Transport: ClientTransport, Input: Sendable, Output: Sendable>(
    request: ClientRequest.Stream<Input>,
    method: MethodDescriptor,
    attempt: Int,
    serializer: some MessageSerializer<Input>,
    deserializer: some MessageDeserializer<Output>,
    interceptors: [any ClientInterceptor],
    streamProcessor: ClientStreamExecutor<Transport>,
    stream: RPCStream<Transport.Inbound, Transport.Outbound>
  ) async -> ClientResponse.Stream<Output> {
    let context = ClientInterceptorContext(descriptor: method)

    return await Self._intercept(
      request: request,
      context: context,
      interceptors: interceptors
    ) { request, context in
      // Let the server know this is a retry.
      var metadata = request.metadata
      if attempt > 1 {
        metadata.previousRPCAttempts = attempt &- 1
      }

      var response = await streamProcessor.execute(
        request: ClientRequest.Stream<[UInt8]>(metadata: metadata) { writer in
          try await request.producer(.serializing(into: writer, with: serializer))
        },
        method: context.descriptor,
        stream: stream
      )

      // Attach the number of previous attempts, it can be useful information for callers.
      if attempt > 1 {
        switch response.accepted {
        case .success(var contents):
          contents.metadata.previousRPCAttempts = attempt &- 1
          response.accepted = .success(contents)

        case .failure(var error):
          error.metadata.previousRPCAttempts = attempt &- 1
          response.accepted = .failure(error)
        }
      }

      return response.map { bytes in
        try deserializer.deserialize(bytes)
      }
    }
  }

  @inlinable
  static func _intercept<Input, Output>(
    request: ClientRequest.Stream<Input>,
    context: ClientInterceptorContext,
    interceptors: [any ClientInterceptor],
    finally: @escaping @Sendable (
      _ request: ClientRequest.Stream<Input>,
      _ context: ClientInterceptorContext
    ) async -> ClientResponse.Stream<Output>
  ) async -> ClientResponse.Stream<Output> {
    return await self._intercept(
      request: request,
      context: context,
      iterator: interceptors.makeIterator(),
      finally: finally
    )
  }

  @inlinable
  static func _intercept<Input, Output>(
    request: ClientRequest.Stream<Input>,
    context: ClientInterceptorContext,
    iterator: Array<any ClientInterceptor>.Iterator,
    finally: @escaping @Sendable (
      _ request: ClientRequest.Stream<Input>,
      _ context: ClientInterceptorContext
    ) async -> ClientResponse.Stream<Output>
  ) async -> ClientResponse.Stream<Output> {
    var iterator = iterator

    switch iterator.next() {
    case .some(let interceptor):
      let iter = iterator
      do {
        return try await interceptor.intercept(request: request, context: context) {
          await self._intercept(request: $0, context: $1, iterator: iter, finally: finally)
        }
      } catch let error as RPCError {
        return ClientResponse.Stream(error: error)
      } catch let other {
        let error = RPCError(code: .unknown, message: "", cause: other)
        return ClientResponse.Stream(error: error)
      }

    case .none:
      return await finally(request, context)
    }
  }
}
