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
  @usableFromInline
  struct HedgingExecutor<
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
    let policy: HedgingPolicy
    @usableFromInline
    let timeout: Duration?
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
      policy: HedgingPolicy,
      timeout: Duration?,
      interceptors: [any ClientInterceptor],
      serializer: Serializer,
      deserializer: Deserializer,
      bufferSize: Int
    ) {
      self.transport = transport
      self.policy = policy
      self.timeout = timeout
      self.interceptors = interceptors
      self.serializer = serializer
      self.deserializer = deserializer
      self.bufferSize = bufferSize
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ClientRPCExecutor.HedgingExecutor {
  @inlinable
  func execute<R: Sendable>(
    request: ClientRequest.Stream<Input>,
    method: MethodDescriptor,
    responseHandler: @Sendable @escaping (ClientResponse.Stream<Output>) async throws -> R
  ) async throws -> R {
    // The high level approach is to have two levels of task group. In the outer level tasks are
    // run to:
    // - run a timeout task (if necessary),
    // - run the request producer so that it writes into a broadcast sequence
    // - run the inner task group.
    //
    // An inner task group runs a number of RPC attempts which may run concurrently. It's
    // responsible for tracking the responses from the server, potentially using one and cancelling
    // all other in flight attempts. Each attempt is started at a fixed interval unless the server
    // explicitly overrides the period using "pushback".
    let result = await withTaskGroup(of: _HedgingTaskResult<R>.self) { group in
      if let timeout = self.timeout {
        group.addTask {
          let result = await Result {
            try await Task.sleep(for: timeout, clock: .continuous)
          }
          return .timedOut(result)
        }
      }

      // Play the original request into the broadcast sequence and construct a replayable request.
      let broadcast = BroadcastAsyncSequence<Input>.makeStream(bufferSize: self.bufferSize)
      group.addTask {
        let result = await Result {
          try await request.producer(RPCWriter(wrapping: broadcast.continuation))
        }
        broadcast.continuation.finish(with: result)
        return .finishedRequest(result)
      }

      group.addTask {
        let replayableRequest = ClientRequest.Stream(metadata: request.metadata) { writer in
          try await writer.write(contentsOf: broadcast.stream)
        }

        let result = await self.executeAttempt(
          request: replayableRequest,
          method: method,
          responseHandler: responseHandler
        )

        return .rpcHandled(result)
      }

      for await event in group {
        switch event {
        case .timedOut(let result):
          switch result {
          case .success:
            group.cancelAll()
          case .failure:
            ()  // Cancelled, ignore and keep looping.
          }

        case .finishedRequest(let result):
          switch result {
          case .success:
            ()
          case .failure:
            group.cancelAll()
          }

        case .rpcHandled(let result):
          group.cancelAll()
          return result
        }
      }

      fatalError("Internal inconsistency")
    }

    return try result.get()
  }

  @inlinable
  func executeAttempt<R: Sendable>(
    request: ClientRequest.Stream<Input>,
    method: MethodDescriptor,
    responseHandler: @Sendable @escaping (ClientResponse.Stream<Output>) async throws -> R
  ) async -> Result<R, Error> {
    await withTaskGroup(
      of: _HedgingAttemptTaskResult<R, Output>.self,
      returning: Result<R, Error>.self
    ) { group in
      // The strategy here is to have two types of task running in the group:
      // - To execute an RPC attempt.
      // - To wait some time before starting the next attempt.
      //
      // As multiple attempts run concurrently, each attempt shares a broadcast sequence.
      // When an attempt receives a usable response it will yield its attempt number into the
      // sequence. Each attempt subgroup will also consume the sequence. If an attempt reads a
      // value which is different to its attempt number then it will cancel itself. Each attempt
      // returns back a handled response or the failed response (in case no attempts are
      // successful). Failed responses may also impact when the next attempt is executed via
      // server pushback.
      let picker = BroadcastAsyncSequence.makeStream(of: Int.self, bufferSize: 2)

      // There's a potential race with attempts identifying that they are 'chosen'. Two attempts
      // could succeed at the same time but, only one can yield first, the second wouldn't be aware
      // of this. To avoid this each attempt goes via a state check before yielding to the sequence
      // ensuring that only one response is used. (If this wasn't the case the response handler
      // could be invoked more than once.)
      let state = LockedValueBox(State(policy: self.policy))

      // There's always a first attempt, safe to '!'.
      let (attempt, scheduleNext) = state.withLockedValue({ $0.nextAttemptNumber() })!

      group.addTask {
        let result = await self._startAttempt(
          request: request,
          method: method,
          attempt: attempt,
          state: state,
          picker: picker,
          responseHandler: responseHandler
        )

        return .attemptCompleted(result)
      }

      // Schedule the second attempt.
      var nextScheduledAttempt = ScheduledState()
      if scheduleNext {
        nextScheduledAttempt.schedule(in: &group, pushback: false, delay: self.policy.hedgingDelay)
      }

      // Stop the most recent unusable response in case no response succeeds.
      var unusableResponse: ClientResponse.Stream<Output>?

      while let next = await group.next() {
        switch next {
        case .scheduledAttemptFired(let outcome):
          switch outcome {
          case .ran:
            // Start a new attempt and possibly schedule the next.
            if let (attempt, scheduleNext) = state.withLockedValue({ $0.nextAttemptNumber() }) {
              group.addTask {
                let result = await self._startAttempt(
                  request: request,
                  method: method,
                  attempt: attempt,
                  state: state,
                  picker: picker,
                  responseHandler: responseHandler
                )
                return .attemptCompleted(result)
              }

              // Schedule the next attempt.
              if scheduleNext {
                nextScheduledAttempt.schedule(
                  in: &group,
                  pushback: false,
                  delay: self.policy.hedgingDelay
                )
              }
            }

          case .cancelled:
            // Cancelling also resets the state.
            nextScheduledAttempt.cancel()
          }

        case .attemptCompleted(let outcome):
          switch outcome {
          case .usableResponse(let response):
            // Note: we don't need to cancel other in-flight requests; they will communicate
            // between themselves when one of them is chosen.
            nextScheduledAttempt.cancel()
            return response

          case .unusableResponse(let response, let pushback):
            // Stash the unusable response.
            unusableResponse = response

            switch pushback {
            case .none:
              // If the handle is for a pushback then don't cancel it or schedule a new timer.
              if nextScheduledAttempt.hasPushbackHandle {
                continue
              }

              nextScheduledAttempt.cancel()

              if let (attempt, scheduleNext) = state.withLockedValue({ $0.nextAttemptNumber() }) {
                group.addTask {
                  let result = await self._startAttempt(
                    request: request,
                    method: method,
                    attempt: attempt,
                    state: state,
                    picker: picker,
                    responseHandler: responseHandler
                  )
                  return .attemptCompleted(result)
                }

                // Schedule the next retry.
                if scheduleNext {
                  nextScheduledAttempt.schedule(
                    in: &group,
                    pushback: true,
                    delay: self.policy.hedgingDelay
                  )
                }
              }

            case .retryAfter(let delay):
              nextScheduledAttempt.schedule(in: &group, pushback: true, delay: delay)

            case .stopRetrying:
              // Stop any new attempts from happening. Let any existing attempts play out.
              nextScheduledAttempt.cancel()
            }

          case .noStreamAvailable(let error):
            group.cancelAll()
            return .failure(error)
          }
        }
      }

      // The group always has a task which returns a response. If it's an acceptable response it
      // will be processed and returned in the preceding while loop, this path is therefore only
      // reachable if there was an unusable response so the force unwrap is safe.
      return await Result {
        try await responseHandler(unusableResponse!)
      }
    }
  }

  @inlinable
  func _startAttempt<R>(
    request: ClientRequest.Stream<Input>,
    method: MethodDescriptor,
    attempt: Int,
    state: LockedValueBox<State>,
    picker: (stream: BroadcastAsyncSequence<Int>, continuation: BroadcastAsyncSequence<Int>.Source),
    responseHandler: @Sendable @escaping (ClientResponse.Stream<Output>) async throws -> R
  ) async -> _HedgingAttemptTaskResult<R, Output>.AttemptResult {
    do {
      return try await self.transport.withStream(
        descriptor: method
      ) { stream -> _HedgingAttemptTaskResult<R, Output>.AttemptResult in
        return await withTaskGroup(of: _HedgingAttemptSubtaskResult<Output>.self) { group in
          group.addTask {
            do {
              // The picker stream will have at most one element.
              for try await selectedAttempt in picker.stream {
                return .attemptPicked(selectedAttempt == attempt)
              }
              return .attemptPicked(false)
            } catch {
              return .attemptPicked(false)
            }
          }

          let processor = ClientStreamExecutor(transport: self.transport)

          group.addTask {
            await processor.run()
            return .processorFinished
          }

          group.addTask {
            let response = await ClientRPCExecutor.unsafeExecute(
              request: request,
              method: method,
              attempt: attempt,
              serializer: self.serializer,
              deserializer: self.deserializer,
              interceptors: self.interceptors,
              streamProcessor: processor,
              stream: stream
            )
            return .response(response)
          }

          for await next in group {
            switch next {
            case .attemptPicked(let wasPicked):
              if !wasPicked {
                group.cancelAll()
              }

            case .response(let response):
              switch response.accepted {
              case .success:
                self.transport.retryThrottle.recordSuccess()

                if state.withLockedValue({ $0.receivedUsableResponse() }) {
                  try? await picker.continuation.write(attempt)
                  picker.continuation.finish()
                  let result = await Result { try await responseHandler(response) }
                  return .usableResponse(result)
                } else {
                  // A different attempt succeeded before we were cancelled. Report this as unusable.
                  return .unusableResponse(response, .none)
                }

              case .failure(let error):
                group.cancelAll()

                if self.policy.nonFatalStatusCodes.contains(Status.Code(error.code)) {
                  // The response failed and the status code is non-fatal, we can make another attempt.
                  self.transport.retryThrottle.recordFailure()
                  return .unusableResponse(response, error.metadata.retryPushback)
                } else {
                  // A fatal error code counts as a success to the throttle.
                  self.transport.retryThrottle.recordSuccess()

                  if state.withLockedValue({ $0.receivedUsableResponse() }) {
                    try! await picker.continuation.write(attempt)
                    picker.continuation.finish()
                    let result = await Result { try await responseHandler(response) }
                    return .usableResponse(result)
                  } else {
                    // A different attempt succeeded before we were cancelled. Report this as unusable.
                    return .unusableResponse(response, .none)
                  }
                }
              }

            case .processorFinished:
              // Processor finished, wait for the response outcome.
              ()
            }
          }

          // There's always a task to return a `.response` which we use as a signal to return from
          // the task group in the preceding code. This is therefore unreachable.
          fatalError("Internal inconsistency")
        }
      }
    } catch {
      return .noStreamAvailable(error)
    }
  }

  @usableFromInline
  struct State {
    @usableFromInline
    let _maximumAttempts: Int
    @usableFromInline
    private(set) var attempt: Int
    @usableFromInline
    private(set) var hasUsableResponse: Bool

    @inlinable
    init(policy: HedgingPolicy) {
      self._maximumAttempts = policy.maximumAttempts
      self.attempt = 1
      self.hasUsableResponse = false
    }

    @inlinable
    mutating func receivedUsableResponse() -> Bool {
      if self.hasUsableResponse {
        return false
      } else {
        self.hasUsableResponse = true
        return true
      }
    }

    @inlinable
    mutating func nextAttemptNumber() -> (Int, Bool)? {
      if self.hasUsableResponse || self.attempt > self._maximumAttempts {
        return nil
      } else {
        let attempt = self.attempt
        self.attempt += 1
        return (attempt, self.attempt <= self._maximumAttempts)
      }
    }
  }

  @usableFromInline
  struct ScheduledState {
    @usableFromInline
    var _handle: CancellableTaskHandle?
    @usableFromInline
    var _isPushback: Bool

    @inlinable
    var hasPushbackHandle: Bool {
      self._handle != nil && self._isPushback
    }

    @inlinable
    init() {
      self._handle = nil
      self._isPushback = false
    }

    @inlinable
    mutating func cancel() {
      self._handle?.cancel()
      self._handle = nil
      self._isPushback = false
    }

    @inlinable
    mutating func schedule<R>(
      in group: inout TaskGroup<_HedgingAttemptTaskResult<R, Output>>,
      pushback: Bool,
      delay: Duration
    ) {
      self._handle?.cancel()
      self._isPushback = pushback
      self._handle = group.addCancellableTask {
        do {
          try await Task.sleep(for: delay, clock: .continuous)
          return .scheduledAttemptFired(.ran)
        } catch {
          return .scheduledAttemptFired(.cancelled)
        }
      }
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@usableFromInline
enum _HedgingTaskResult<R> {
  case rpcHandled(Result<R, Error>)
  case finishedRequest(Result<Void, Error>)
  case timedOut(Result<Void, Error>)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@usableFromInline
enum _HedgingAttemptTaskResult<R, Output> {
  case attemptCompleted(AttemptResult)
  case scheduledAttemptFired(ScheduleEvent)

  @usableFromInline
  enum AttemptResult {
    case unusableResponse(ClientResponse.Stream<Output>, Metadata.RetryPushback?)
    case usableResponse(Result<R, Error>)
    case noStreamAvailable(Error)
  }

  @usableFromInline
  enum ScheduleEvent {
    case ran
    case cancelled
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@usableFromInline
enum _HedgingAttemptSubtaskResult<Output> {
  case attemptPicked(Bool)
  case processorFinished
  case response(ClientResponse.Stream<Output>)
}
