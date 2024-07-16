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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ClientRPCExecutor.OneShotExecutor {
  @inlinable
  func execute<R>(
    request: ClientRequest.Stream<Input>,
    method: MethodDescriptor,
    options: CallOptions,
    responseHandler: @Sendable @escaping (ClientResponse.Stream<Output>) async throws -> R
  ) async throws -> R {
    let result = await withTaskGroup(
      of: _OneShotExecutorTask<R>.self,
      returning: Result<R, any Error>.self
    ) { group in
      do {
        return try await self.transport.withStream(descriptor: method, options: options) { stream in
          var request = request

          if let deadline = self.deadline {
            request.metadata.timeout = ContinuousClock.now.duration(to: deadline)
            group.addTask {
              let result = await Result {
                try await Task.sleep(until: deadline, clock: .continuous)
              }
              return .timedOut(result)
            }
          }

          let streamExecutor = ClientStreamExecutor(transport: self.transport)
          group.addTask {
            await streamExecutor.run()
            return .streamExecutorCompleted
          }

          group.addTask { [request] in
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
  case timedOut(Result<Void, any Error>)
  case responseHandled(Result<R, any Error>)
}
