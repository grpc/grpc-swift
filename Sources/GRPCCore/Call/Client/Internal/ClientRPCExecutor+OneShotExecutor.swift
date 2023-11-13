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
extension ClientRPCExecutor {
  /// An executor for requests which doesn't apply retries or hedging. The request has just one
  /// attempt at execution.
  @usableFromInline
  struct OneShotExecutor<
    Transport: ClientTransport,
    Serializer: MessageSerializer,
    Deserializer: MessageDeserializer
  > {
    @usableFromInline
    typealias Input = Serializer.Message
    @usableFromInline
    typealias Output = Deserializer.Message

    @usableFromInline
    let transport: Transport
    @usableFromInline
    let timeout: Duration?
    @usableFromInline
    let interceptors: [any ClientInterceptor]
    @usableFromInline
    let serializer: Serializer
    @usableFromInline
    let deserializer: Deserializer

    @inlinable
    init(
      transport: Transport,
      timeout: Duration?,
      interceptors: [any ClientInterceptor],
      serializer: Serializer,
      deserializer: Deserializer
    ) {
      self.transport = transport
      self.timeout = timeout
      self.interceptors = interceptors
      self.serializer = serializer
      self.deserializer = deserializer
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ClientRPCExecutor.OneShotExecutor {
  @inlinable
  func execute<R>(
    request: ClientRequest.Stream<Input>,
    method: MethodDescriptor,
    responseHandler: @Sendable @escaping (ClientResponse.Stream<Output>) async throws -> R
  ) async throws -> R {
    let result = await withTaskGroup(
      of: _OneShotExecutorTask<R>.self,
      returning: Result<R, Error>.self
    ) { group in
      do {
        return try await self.transport.withStream(descriptor: method) { stream in
          if let timeout = self.timeout {
            group.addTask {
              let result = await Result {
                try await Task.sleep(until: .now.advanced(by: timeout), clock: .continuous)
              }
              return .timedOut(result)
            }
          }

          let streamExecutor = ClientStreamExecutor(transport: self.transport)
          group.addTask {
            await streamExecutor.run()
            return .streamExecutorCompleted
          }

          group.addTask {
            let response = await ClientRPCExecutor.unsafeExecute(
              request: request,
              method: method,
              attempt: 1,
              serializer: self.serializer,
              deserializer: self.deserializer,
              interceptors: self.interceptors,
              streamProcessor: streamExecutor,
              stream: stream
            )

            let result = await Result {
              try await responseHandler(response)
            }

            return .responseHandled(result)
          }

          while let result = await group.next() {
            switch result {
            case .streamExecutorCompleted:
              // Stream finished; wait for the response to be handled.
              ()

            case .timedOut(.success):
              // The deadline passed; cancel the ongoing work group.
              group.cancelAll()

            case .timedOut(.failure):
              // The deadline task failed (because the task was cancelled). Wait for the response
              // to be handled.
              ()

            case .responseHandled(let result):
              // Response handled: cancel any other remaining tasks.
              group.cancelAll()
              return result
            }
          }

          // Unreachable: exactly one task returns `responseHandled` and we return when it completes.
          fatalError("Internal inconsistency")
        }
      } catch {
        return .failure(error)
      }
    }

    return try result.get()
  }
}

@usableFromInline
enum _OneShotExecutorTask<R> {
  case streamExecutorCompleted
  case timedOut(Result<Void, Error>)
  case responseHandled(Result<R, Error>)
}
