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
  @usableFromInline
  struct RetryExecutor<
    Transport: ClientTransport,
    Input: Sendable,
    Output: Sendable,
    Serializer: MessageSerializer,
    Deserializer: MessageDeserializer
  >: Sendable where Serializer.Message == Input, Deserializer.Message == Output {
    @usableFromInline
    let transport: Transport
    @usableFromInline
    let policy: RetryPolicy
    @usableFromInline
    let deadline: ContinuousClock.Instant?
    @usableFromInline
    let interceptors: [any ClientInterceptor]
    @usableFromInline
    let serializer: Serializer
    @usableFromInline
    let deserializer: Deserializer
    @usableFromInline
    let bufferSize: Int

    @inlinable
    init(
      transport: Transport,
      policy: RetryPolicy,
      deadline: ContinuousClock.Instant?,
      interceptors: [any ClientInterceptor],
      serializer: Serializer,
      deserializer: Deserializer,
      bufferSize: Int
    ) {
      self.transport = transport
      self.policy = policy
      self.deadline = deadline
      self.interceptors = interceptors
      self.serializer = serializer
      self.deserializer = deserializer
      self.bufferSize = bufferSize
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ClientRPCExecutor.RetryExecutor {
  @inlinable
  func execute<R: Sendable>(
    request: ClientRequest.Stream<Input>,
    method: MethodDescriptor,
    options: CallOptions,
    responseHandler: @Sendable @escaping (ClientResponse.Stream<Output>) async throws -> R
  ) async throws -> R {
    // There's quite a lot going on here...
    //
    // The high level approach is to have two levels of task group. In the outer level tasks are
    // run to:
    // - run a timeout task (if necessary),
    // - run the request producer so that it writes into a broadcast sequence (in this instance we
    //   don't care about broadcasting but the sequence's ability to replay)
    // - run the inner task group.
    //
    // An inner task group is run for each RPC attempt. We might also pause between attempts. The
    // inner group runs two tasks:
    // - a stream executor, and
    // - the unsafe RPC executor which inspects the response, either passing it to the handler or
    //   deciding a retry should be undertaken.
    //
    // It is also worth noting that the server can override the retry delay using "pushback" and
    // retries may be skipped if the throttle is applied.
    let result = await withTaskGroup(
      of: _RetryExecutorTask<R>.self,
      returning: Result<R, any Error>.self
    ) { group in
      // Add a task to limit the overall execution time of the RPC.
      if let deadline = self.deadline {
        group.addTask {
          let result = await Result {
            try await Task.sleep(until: deadline, clock: .continuous)
          }
          return .timedOut(result)
        }
      }

      // Play the original request into the broadcast sequence and construct a replayable request.
      let retry = BroadcastAsyncSequence<Input>.makeStream(bufferSize: self.bufferSize)
      group.addTask {
        let result = await Result {
          try await request.producer(RPCWriter(wrapping: retry.continuation))
        }
        retry.continuation.finish(with: result)
        return .outboundFinished(result)
      }

      // The sequence isn't limited by the number of attempts as the iterator is reset when the
      // server applies pushback.
      let delaySequence = RetryDelaySequence(policy: self.policy)
      var delayIterator = delaySequence.makeIterator()

      for attempt in 1 ... self.policy.maxAttempts {
        do {
          let attemptResult = try await self.transport.withStream(
            descriptor: method,
            options: options
          ) { stream in
            group.addTask {
              var metadata = request.metadata
              // Work out the timeout from the deadline.
              if let deadline = self.deadline {
                metadata.timeout = ContinuousClock.now.duration(to: deadline)
              }

              return await self.executeAttempt(
                stream: stream,
                metadata: metadata,
                retryStream: retry.stream,
                method: method,
                attempt: attempt,
                responseHandler: responseHandler
              )
            }

            loop: while let next = await group.next() {
              switch next {
              case .handledResponse(let result):
                // A usable response; cancel the remaining work and return the result.
                group.cancelAll()
                return Optional.some(result)

              case .retry(let delayOverride):
                // The attempt failed, wait a bit and then retry. The server might have overridden the
                // delay via pushback so preferentially use that value.
                //
                // Any error will come from cancellation: if it happens while we're sleeping we can
                // just loop around, the next attempt will be cancelled immediately and we will return
                // its response to the client.
                if let delayOverride = delayOverride {
                  // If the delay is overridden with server pushback then reset the iterator for the
                  // next retry.
                  delayIterator = delaySequence.makeIterator()
                  try? await Task.sleep(until: .now.advanced(by: delayOverride), clock: .continuous)
                } else {
                  // The delay iterator never terminates.
                  try? await Task.sleep(
                    until: .now.advanced(by: delayIterator.next()!),
                    clock: .continuous
                  )
                }

                break loop  // from the while loop so another attempt can be started.

              case .timedOut(.success), .outboundFinished(.failure):
                // Timeout task fired successfully or failed to process the outbound stream. Cancel and
                // wait for a usable response (which is likely to be an error).
                group.cancelAll()

              case .timedOut(.failure), .outboundFinished(.success):
                // Timeout task failed which means it was cancelled (so no need to cancel again) or the
                // outbound stream was successfully processed (so don't need to do anything).
                ()
              }
            }
            return nil
          }

          if let attemptResult {
            return attemptResult
          }
        } catch {
          return .failure(error)
        }
      }
      fatalError("Internal inconsistency")
    }

    return try result.get()
  }

  @inlinable
  func executeAttempt<R: Sendable>(
    stream: RPCStream<ClientTransport.Inbound, ClientTransport.Outbound>,
    metadata: Metadata,
    retryStream: BroadcastAsyncSequence<Input>,
    method: MethodDescriptor,
    attempt: Int,
    responseHandler: @Sendable @escaping (ClientResponse.Stream<Output>) async throws -> R
  ) async -> _RetryExecutorTask<R> {
    return await withTaskGroup(
      of: Void.self,
      returning: _RetryExecutorTask<R>.self
    ) { group in
      let request = ClientRequest.Stream(metadata: metadata) {
        try await $0.write(contentsOf: retryStream)
      }

      let response = await ClientRPCExecutor._execute(
        in: &group,
        request: request,
        method: method,
        attempt: attempt,
        serializer: self.serializer,
        deserializer: self.deserializer,
        interceptors: self.interceptors,
        stream: stream
      )

      let shouldRetry: Bool
      let retryDelayOverride: Duration?

      switch response.accepted {
      case .success:
        // Request was accepted. This counts as success to the throttle and there's no need
        // to retry.
        self.transport.retryThrottle?.recordSuccess()
        retryDelayOverride = nil
        shouldRetry = false

      case .failure(let error):
        // The request was rejected. Determine whether a retry should be carried out. The
        // following conditions must be checked:
        //
        // - Whether the status code is retryable.
        // - Whether more attempts are permitted by the config.
        // - Whether the throttle permits another retry to be carried out.
        // - Whether the server pushed back to either stop further retries or to override
        //   the delay before the next retry.
        let code = Status.Code(error.code)
        let isRetryableStatusCode = self.policy.retryableStatusCodes.contains(code)

        if isRetryableStatusCode {
          // Counted as failure for throttling.
          let throttled = self.transport.retryThrottle?.recordFailure() ?? false

          // Status code can be retried, Did the server send pushback?
          switch error.metadata.retryPushback {
          case .retryAfter(let delay):
            // Pushback: only retry if our config permits it.
            shouldRetry = (attempt < self.policy.maxAttempts) && !throttled
            retryDelayOverride = delay
          case .stopRetrying:
            // Server told us to stop trying.
            shouldRetry = false
            retryDelayOverride = nil
          case .none:
            // No pushback: only retry if our config permits it.
            shouldRetry = (attempt < self.policy.maxAttempts) && !throttled
            retryDelayOverride = nil
            break
          }
        } else {
          // Not-retryable; this is considered a success.
          self.transport.retryThrottle?.recordSuccess()
          shouldRetry = false
          retryDelayOverride = nil
        }
      }

      if shouldRetry {
        // Cancel subscribers of the broadcast sequence. This is safe as we are the only
        // subscriber and maximises the chances that 'isKnownSafeForNextSubscriber' will
        // return true.
        //
        // Note: this must only be called if we should retry, otherwise we may cancel a
        // subscriber for an accepted request.
        retryStream.invalidateAllSubscriptions()

        // Only retry if we know it's safe for the next subscriber, that is, the first
        // element is still in the buffer. It's safe to call this because there's only
        // ever one attempt at a time and the existing subscribers have been invalidated.
        if retryStream.isKnownSafeForNextSubscriber {
          return .retry(retryDelayOverride)
        }
      }

      // Not retrying or not safe to retry.
      let result = await Result {
        // Check for cancellation; the RPC may have timed out in which case we should skip
        // the response handler.
        try Task.checkCancellation()
        return try await responseHandler(response)
      }
      return .handledResponse(result)
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@usableFromInline
enum _RetryExecutorTask<R: Sendable>: Sendable {
  case timedOut(Result<Void, any Error>)
  case handledResponse(Result<R, any Error>)
  case retry(Duration?)
  case outboundFinished(Result<Void, any Error>)
}
