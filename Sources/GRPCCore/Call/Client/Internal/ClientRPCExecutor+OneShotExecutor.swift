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

extension ClientRPCExecutor {
  /// An executor for requests which doesn't apply retries or hedging. The request has just one
  /// attempt at execution.
  @usableFromInline
  struct OneShotExecutor<
    Transport: ClientTransport,
    Input: Sendable,
    Output: Sendable,
    Serializer: MessageSerializer,
    Deserializer: MessageDeserializer
  >: Sendable where Serializer.Message == Input, Deserializer.Message == Output {
    @usableFromInline
    let transport: Transport
    @usableFromInline
    let deadline: ContinuousClock.Instant?
    @usableFromInline
    let interceptors: [any ClientInterceptor]
    @usableFromInline
    let serializer: Serializer
    @usableFromInline
    let deserializer: Deserializer

    @inlinable
    init(
      transport: Transport,
      deadline: ContinuousClock.Instant?,
      interceptors: [any ClientInterceptor],
      serializer: Serializer,
      deserializer: Deserializer
    ) {
      self.transport = transport
      self.deadline = deadline
      self.interceptors = interceptors
      self.serializer = serializer
      self.deserializer = deserializer
    }
  }
}

extension ClientRPCExecutor.OneShotExecutor {
  @inlinable
  func execute<R: Sendable>(
    request: StreamingClientRequest<Input>,
    method: MethodDescriptor,
    options: CallOptions,
    responseHandler: @Sendable @escaping (StreamingClientResponse<Output>) async throws -> R
  ) async throws -> R {
    let result: Result<R, any Error>

    if let deadline = self.deadline {
      var request = request
      request.metadata.timeout = ContinuousClock.now.duration(to: deadline)
      let immutableRequest = request
      result = await withDeadline(deadline) {
        await self._execute(
          request: immutableRequest,
          method: method,
          options: options,
          responseHandler: responseHandler
        )
      }
    } else {
      result = await self._execute(
        request: request,
        method: method,
        options: options,
        responseHandler: responseHandler
      )
    }

    return try result.get()
  }
}

extension ClientRPCExecutor.OneShotExecutor {
  @inlinable
  func _execute<R: Sendable>(
    request: StreamingClientRequest<Input>,
    method: MethodDescriptor,
    options: CallOptions,
    responseHandler: @Sendable @escaping (StreamingClientResponse<Output>) async throws -> R
  ) async -> Result<R, any Error> {
    return await withTaskGroup(of: Void.self, returning: Result<R, any Error>.self) { group in
      do {
        return try await self.transport.withStream(descriptor: method, options: options) { stream, context in
          let response = await ClientRPCExecutor._execute(
            in: &group,
            context: context,
            request: request,
            attempt: 1,
            serializer: self.serializer,
            deserializer: self.deserializer,
            interceptors: self.interceptors,
            stream: stream
          )

          let result = await Result {
            try await responseHandler(response)
          }

          // The user handler can finish before the stream. Cancel it if that's the case.
          group.cancelAll()

          return result
        }
      } catch {
        return .failure(error)
      }
    }
  }
}

@inlinable
func withDeadline<Result: Sendable>(
  _ deadline: ContinuousClock.Instant,
  execute: @Sendable @escaping () async -> Result
) async -> Result {
  return await withTaskGroup(of: _DeadlineChildTaskResult<Result>.self) { group in
    group.addTask {
      do {
        try await Task.sleep(until: deadline)
        return .deadlinePassed
      } catch {
        return .timeoutCancelled
      }
    }

    group.addTask {
      let result = await execute()
      return .taskCompleted(result)
    }

    while let next = await group.next() {
      switch next {
      case .deadlinePassed:
        // Timeout expired; cancel the work.
        group.cancelAll()

      case .timeoutCancelled:
        ()  // Wait for more tasks to finish.

      case .taskCompleted(let result):
        // The work finished. Cancel any remaining tasks.
        group.cancelAll()
        return result
      }
    }

    fatalError("Internal inconsistency")
  }
}

@usableFromInline
enum _DeadlineChildTaskResult<Value: Sendable>: Sendable {
  case deadlinePassed
  case timeoutCancelled
  case taskCompleted(Value)
}
