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
    let result = await withTaskGroup(of: _HedgeTaskResult<R>.self) { group in
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
        broadcast.continuation.finish()
        return .processedRequest(result)
      }

      group.addTask {
        let replayableRequest = ClientRequest.Stream(metadata: request.metadata) { writer in
          try await writer.write(contentsOf: broadcast.stream)
        }

        let result = await self._execute(
          request: replayableRequest,
          method: method,
          responseHandler: responseHandler
        )

        return .workCompleted(result)
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

        case .processedRequest(let result):
          switch result {
          case .success:
            ()
          case .failure:
            group.cancelAll()
          }

        case .workCompleted(let result):
          group.cancelAll()
          return result
        }
      }

      fatalError("Internal inconsistency")
    }

    return try result.get()
  }

  @inlinable
  func _execute<R>(
    request: ClientRequest.Stream<Input>,
    method: MethodDescriptor,
    responseHandler: @Sendable @escaping (ClientResponse.Stream<Output>) async throws -> R
  ) async -> Result<R, Error> {
    return await withTaskGroup(of: Void.self, returning: Result<R, Error>.self) { group in
      var state = HedgingStateMachine(policy: policy, throttle: self.transport.retryThrottle)
      let event = AsyncStream.makeStream(of: _HedgingEvent<Output>.self)
      // Queue up the first attempt.
      event.continuation.yield(.start)

      var lastResponse: ClientResponse.Stream<Output>?

      for await hedgingEvent in event.stream {
        switch hedgingEvent {
        case .start:
          switch state.startNext() {
          case .abort(let scheduled):
            event.continuation.finish()
            group.cancelAll()
            _ = await scheduled?.cancel()
            break

          case .startAttempt(let attempt, let delay):
            if let delay = delay {
              let scheduled = HedgingStateMachine.ScheduledAttempt(after: delay) {
                event.continuation.yield(.start)
              }
              state.setNextHedgeDelayTimer(scheduled)
            }

            group.addTask {
              // Add a hedging attempt to process.
              let processor = ClientStreamExecutor(transport: self.transport)
              let processorTask = Task { await processor.run() }
              let response = await ClientRPCExecutor.unsafeExecute(
                request: request,
                method: method,
                attempt: attempt,
                serializer: self.serializer,
                deserializer: self.deserializer,
                interceptors: self.interceptors,
                streamProcessor: processor
              )

              switch event.continuation.yield(.receivedResponse(response, processorTask)) {
              case .enqueued:
                ()
              case .dropped, .terminated:
                fallthrough
              @unknown default:
                processorTask.cancel()
                _ = await processorTask.value
              }
            }

          case .none:
            ()
          }

        case .receivedResponse(let response, let processor):
          switch state.receivedResponse(response.accepted.map { _ in }) {
          case .scheduleNextAttempt(let delay, let existing):
            // Stash the response in case we need it later.
            lastResponse = response

            // Cancel and wait for the processor to finish.
            processor.cancel()
            _ = await processor.value

            let shouldSchedule = await existing?.cancel() ?? true
            guard shouldSchedule else {
              continue
            }

            if let delay = delay {
              let scheduled = HedgingStateMachine.ScheduledAttempt(after: delay) {
                event.continuation.yield(.start)
              }
              state.setNextHedgeDelayTimer(scheduled)
            } else {
              event.continuation.yield(.start)
            }

          case .use(let scheduled):
            event.continuation.finish()
            // Cancel the group and the next scheduled attempt.
            group.cancelAll()
            // Cancel any other requests.
            _ = await scheduled?.cancel()

            // Now handle the response.
            let result = await Result {
              try await responseHandler(response)
            }

            // The response has completed, so cancel the processor now.
            processor.cancel()
            _ = await processor.value

            return result

          case .none:
            ()
          }

        case .timedOut:
          group.cancelAll()
          switch state.cancel() {
          case .cancel(let scheduled):
            _ = await scheduled.cancel()
          case .none:
            ()
          }

        case .processedRequest(let result):
          switch result {
          case .success:
            ()
          case .failure:
            group.cancelAll()
            switch state.cancel() {
            case .cancel(let scheduled):
              _ = await scheduled.cancel()
            case .none:
              ()
            }
          }
        }
      }

      if let lastResponse = lastResponse {
        return await Result {
          try await responseHandler(lastResponse)
        }
      } else {
        return .failure(CancellationError())
      }
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@usableFromInline
struct HedgingStateMachine {
  /// The policy used for hedging this request.
  @usableFromInline
  let policy: HedgingPolicy
  /// The current attempt.
  @usableFromInline
  var attempt = 1
  /// The number of inflight requests.
  @usableFromInline
  var outstanding = 0
  /// Retry throttle.
  @usableFromInline
  let throttle: RetryThrottle
  /// The next scheduled attempt.
  @usableFromInline
  var nextAttempt: ScheduledAttempt?

  @usableFromInline
  struct ScheduledAttempt {
    @usableFromInline
    let task: Task<Void, Error>

    @inlinable
    init(after delay: Duration, _ body: @Sendable @escaping () -> Void) {
      self.task = Task {
        try await Task.sleep(for: delay, clock: .continuous)
        body()
      }
    }

    @inlinable
    func cancel() async -> Bool {
      self.task.cancel()
      switch await self.task.result {
      case .success:
        return false
      case .failure:
        return true
      }
    }
  }

  @inlinable
  init(policy: HedgingPolicy, throttle: RetryThrottle) {
    self.policy = policy
    self.throttle = throttle
  }

  @usableFromInline
  enum OnResponse {
    case none
    case use(cancel: ScheduledAttempt?)
    case scheduleNextAttempt(Duration?, cancel: ScheduledAttempt?)
  }

  @inlinable
  mutating func receivedResponse(_ result: Result<Void, RPCError>) -> OnResponse {
    self.outstanding &-= 1
    switch result {
    case .success:
      return self.receivedOKResponse()
    case .failure(let error):
      return self.receivedErrorResponse(error)
    }
  }

  @inlinable
  mutating func receivedOKResponse() -> OnResponse {
    self.throttle.recordSuccess()
    return .use(cancel: self.nextAttempt.take())
  }

  @inlinable
  mutating func receivedErrorResponse(_ error: RPCError) -> OnResponse {
    let code = Status.Code(error.code)
    let isNonFatal = self.policy.nonFatalStatusCodes.contains(code)

    guard isNonFatal else {
      // Fatal error code. Use the response.
      self.throttle.recordSuccess()
      return .use(cancel: self.nextAttempt.take())
    }

    // The status code is non fatal, so record a failure.
    self.throttle.recordFailure()

    guard self.attempt <= self.policy.maximumAttempts else {
      // If there are no outstanding RPCs use the response, otherwise wait.
      return self.outstanding == 0 ? .use(cancel: self.nextAttempt.take()) : .none
    }

    let onResponse: OnResponse
    switch error.metadata.retryPushback {
    case .retryAfter(let delay):
      // Pushback is valid, cancel the timer for the next attempt and use the value provided by
      // the server.
      onResponse = .scheduleNextAttempt(delay, cancel: self.nextAttempt.take())

    case .stopRetrying:
      // Server indicated we should stop trying. Use this response.
      onResponse = .use(cancel: self.nextAttempt.take())

    case .none:
      // No pushback. Retry immediately if no attempt is scheduled, otherwise schedule the next
      // attempt.
      if let nextAttempt = self.nextAttempt.take() {
        onResponse = .scheduleNextAttempt(nil, cancel: nextAttempt)
      } else {
        onResponse = .scheduleNextAttempt(self.policy.hedgingDelay, cancel: nil)
      }
    }

    return onResponse
  }

  @inlinable
  mutating func setNextHedgeDelayTimer(_ scheduled: ScheduledAttempt) {
    precondition(self.nextAttempt == nil)
    self.nextAttempt = scheduled
  }

  @usableFromInline
  enum OnNext {
    case none
    case startAttempt(Int, Duration?)
    case abort(ScheduledAttempt?)
  }

  @inlinable
  mutating func startNext() -> OnNext {
    self.nextAttempt = nil

    guard self.attempt > 1 else {
      // First attempt is always allowed.
      defer {
        self.outstanding &+= 1
        self.attempt &+= 1
      }

      assert(self.nextAttempt == nil)
      return .startAttempt(self.attempt, self.policy.hedgingDelay)
    }

    guard self.throttle.isRetryPermitted, self.attempt <= self.policy.maximumAttempts else {
      if self.outstanding == 0 {
        return .abort(self.nextAttempt.take())
      } else {
        return .none
      }
    }

    defer {
      self.outstanding &+= 1
      self.attempt &+= 1
    }

    if self.nextAttempt == nil {
      return .startAttempt(self.attempt, self.policy.hedgingDelay)
    } else {
      return .startAttempt(self.attempt, nil)
    }
  }

  @usableFromInline
  enum OnCancel {
    case none
    case cancel(ScheduledAttempt)
  }

  @inlinable
  mutating func cancel() -> OnCancel {
    if let scheduled = self.nextAttempt.take() {
      return .cancel(scheduled)
    } else {
      return .none
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
enum _HedgingEvent<Output> {
  case start
  case timedOut
  case processedRequest(Result<Void, Error>)
  case receivedResponse(ClientResponse.Stream<Output>, Task<Void, Never>)
}

@usableFromInline
enum _HedgeTaskResult<R> {
  case workCompleted(Result<R, Error>)
  case processedRequest(Result<Void, Error>)
  case timedOut(Result<Void, Error>)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension HedgingStateMachine.ScheduledAttempt? {
  @inlinable
  mutating func take() -> Self {
    if let some = self {
      self = .none
      return some
    } else {
      return .none
    }
  }
}
