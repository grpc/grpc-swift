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

@available(gRPCSwift 2.0, *)
@usableFromInline
enum ClientRPCExecutor {
  /// Execute the request and handle its response.
  ///
  /// - Parameters:
  ///   - request: The request to execute.
  ///   - method: A description of the method to execute the request against.
  ///   - options: RPC options.
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
    request: StreamingClientRequest<Input>,
    method: MethodDescriptor,
    options: CallOptions,
    serializer: some MessageSerializer<Input>,
    deserializer: some MessageDeserializer<Output>,
    transport: some ClientTransport,
    interceptors: [any ClientInterceptor],
    handler: @Sendable @escaping (StreamingClientResponse<Output>) async throws -> Result
  ) async throws -> Result {
    let deadline = options.timeout.map { ContinuousClock.now + $0 }

    switch options.executionPolicy?.wrapped {
    case .none:
      let oneShotExecutor = OneShotExecutor(
        transport: transport,
        deadline: deadline,
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
        deadline: deadline,
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
        deadline: deadline,
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

@available(gRPCSwift 2.0, *)
extension ClientRPCExecutor {
  /// Executes a request on a given stream processor.
  ///
  /// - Parameters:
  ///   - request: The request to execute.
  ///   - context: The ``ClientContext`` related to this request.
  ///   - attempt: The attempt number of the request.
  ///   - serializer: A serializer to convert input messages to bytes.
  ///   - deserializer: A deserializer to convert bytes to output messages.
  ///   - interceptors: An array of interceptors which the request and response pass through. The
  ///       interceptors will be called in the order of the array.
  ///   - stream: The stream to execute the RPC on.
  /// - Returns: The deserialized response.
  @inlinable  // would be private
  static func _execute<Input: Sendable, Output: Sendable, Bytes: GRPCContiguousBytes>(
    in group: inout TaskGroup<Void>,
    context: ClientContext,
    request: StreamingClientRequest<Input>,
    attempt: Int,
    serializer: some MessageSerializer<Input>,
    deserializer: some MessageDeserializer<Output>,
    interceptors: [any ClientInterceptor],
    stream: RPCStream<
      RPCAsyncSequence<RPCResponsePart<Bytes>, any Error>,
      RPCWriter<RPCRequestPart<Bytes>>.Closable
    >
  ) async -> StreamingClientResponse<Output> {

    if interceptors.isEmpty {
      return await ClientStreamExecutor.execute(
        in: &group,
        request: request,
        context: context,
        attempt: attempt,
        serializer: serializer,
        deserializer: deserializer,
        stream: stream
      )
    } else {
      return await Self._intercept(
        in: &group,
        request: request,
        context: context,
        iterator: interceptors.makeIterator()
      ) { group, request, context in
        return await ClientStreamExecutor.execute(
          in: &group,
          request: request,
          context: context,
          attempt: attempt,
          serializer: serializer,
          deserializer: deserializer,
          stream: stream
        )
      }
    }
  }

  @inlinable
  static func _intercept<Input, Output>(
    in group: inout TaskGroup<Void>,
    request: StreamingClientRequest<Input>,
    context: ClientContext,
    iterator: Array<any ClientInterceptor>.Iterator,
    finally: (
      _ group: inout TaskGroup<Void>,
      _ request: StreamingClientRequest<Input>,
      _ context: ClientContext
    ) async -> StreamingClientResponse<Output>
  ) async -> StreamingClientResponse<Output> {
    var iterator = iterator

    switch iterator.next() {
    case .some(let interceptor):
      let iter = iterator
      do {
        return try await interceptor.intercept(request: request, context: context) {
          await self._intercept(
            in: &group,
            request: $0,
            context: $1,
            iterator: iter,
            finally: finally
          )
        }
      } catch let error as RPCError {
        return StreamingClientResponse(error: error)
      } catch let error as any RPCErrorConvertible {
        return StreamingClientResponse(error: RPCError(error))
      } catch let other {
        let error = RPCError(code: .unknown, message: "", cause: other)
        return StreamingClientResponse(error: error)
      }

    case .none:
      return await finally(&group, request, context)
    }
  }
}
