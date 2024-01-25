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
import DequeModule

/// An `AsyncSequence` which can broadcast its values to multiple consumers concurrently.
///
/// The sequence is not a general-purpose broadcast sequence; it is tailored specifically for the
/// requirements of gRPC Swift, in particular it is used to support retrying and hedging requests.
///
/// In order to achieve this it maintains on an internal buffer of elements which is limited in
/// size. Each iterator ("subscriber") maintains an offset into the elements which the sequence has
/// produced over time. If a subscriber is consuming too slowly (and the buffer is full) then the
/// sequence will cancel the subscriber's subscription to the stream, dropping the oldest element
/// in the buffer to make space for more elements. If the buffer is full and all subscribers are
/// equally slow then all producers are suspended until the buffer drops to a reasonable size.
///
/// The expectation is that the number of subscribers will be low; for retries there will be at most
/// one subscriber at a time, for hedging there may be at most five subscribers at a time.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
struct BroadcastAsyncSequence<Element: Sendable>: Sendable, AsyncSequence {
  @usableFromInline
  let _storage: _BroadcastSequenceStorage<Element>

  @inlinable
  init(_storage: _BroadcastSequenceStorage<Element>) {
    self._storage = _storage
  }

  /// Make a new stream and continuation.
  ///
  /// - Parameters:
  ///   - elementType: The type of element this sequence produces.
  ///   - bufferSize: The number of elements this sequence may store.
  /// - Returns: A stream and continuation.
  @inlinable
  static func makeStream(
    of elementType: Element.Type = Element.self,
    bufferSize: Int
  ) -> (stream: Self, continuation: Self.Source) {
    let storage = _BroadcastSequenceStorage<Element>(bufferSize: bufferSize)
    let stream = Self(_storage: storage)
    let continuation = Self.Source(_storage: storage)
    return (stream, continuation)
  }

  @inlinable
  func makeAsyncIterator() -> AsyncIterator {
    let id = self._storage.subscribe()
    return AsyncIterator(_storage: _storage, id: id)
  }

  /// Returns true if it is known to be safe for the next subscriber to subscribe and successfully
  /// consume elements.
  ///
  /// This function can return `false` if there are active subscribers or the internal buffer no
  /// longer contains the first element in the sequence.
  @inlinable
  var isKnownSafeForNextSubscriber: Bool {
    self._storage.isKnownSafeForNextSubscriber
  }

  /// Invalidates all active subscribers.
  ///
  /// Any active subscriber will receive an error the next time they attempt to consume an element.
  @inlinable
  func invalidateAllSubscriptions() {
    self._storage.invalidateAllSubscriptions()
  }
}

// MARK: - AsyncIterator

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension BroadcastAsyncSequence {
  @usableFromInline
  struct AsyncIterator: AsyncIteratorProtocol {
    @usableFromInline
    let _storage: _BroadcastSequenceStorage<Element>
    @usableFromInline
    let _subscriberID: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID

    @inlinable
    init(
      _storage: _BroadcastSequenceStorage<Element>,
      id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID
    ) {
      self._storage = _storage
      self._subscriberID = id
    }

    @inlinable
    mutating func next() async throws -> Element? {
      try await self._storage.nextElement(forSubscriber: self._subscriberID)
    }
  }
}

// MARK: - Continuation

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension BroadcastAsyncSequence {
  @usableFromInline
  struct Source: Sendable {
    @usableFromInline
    let _storage: _BroadcastSequenceStorage<Element>

    @usableFromInline
    init(_storage: _BroadcastSequenceStorage<Element>) {
      self._storage = _storage
    }

    @inlinable
    func write(_ element: Element) async throws {
      try await self._storage.yield(element)
    }

    @inlinable
    func finish(with result: Result<Void, Error>) {
      self._storage.finish(result)
    }

    @inlinable
    func finish() {
      self.finish(with: .success(()))
    }

    @inlinable
    func finish(throwing error: Error) {
      self.finish(with: .failure(error))
    }
  }
}

@usableFromInline
enum BroadcastAsyncSequenceError: Error {
  /// The consumer was too slow.
  case consumingTooSlow
  /// The producer has already finished.
  case productionAlreadyFinished
}

// MARK: - Storage

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
final class _BroadcastSequenceStorage<Element: Sendable>: Sendable {
  @usableFromInline
  let _state: LockedValueBox<_BroadcastSequenceStateMachine<Element>>

  @inlinable
  init(bufferSize: Int) {
    self._state = LockedValueBox(_BroadcastSequenceStateMachine(bufferSize: bufferSize))
  }

  deinit {
    let onDrop = self._state.withLockedValue { state in
      state.dropResources()
    }

    switch onDrop {
    case .none:
      ()
    case .resume(let consumers, let producers):
      consumers.resume()
      producers.resume()
    }
  }

  // MARK - Producer

  /// Yield a single element to the stream. Suspends if the stream's buffer is full.
  ///
  /// - Parameter element: The element to write.
  @inlinable
  func yield(_ element: Element) async throws {
    let onYield = self._state.withLockedValue { state in state.yield(element) }

    switch onYield {
    case .none:
      ()

    case .resume(let continuations):
      continuations.resume()

    case .suspend(let token):
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let onProduceMore = self._state.withLockedValue { state in
            state.waitToProduceMore(continuation: continuation, token: token)
          }

          switch onProduceMore {
          case .resume(let continuation, let result):
            continuation.resume(with: result)
          case .none:
            ()
          }
        }
      } onCancel: {
        let onCancel = self._state.withLockedValue { state in
          state.cancelProducer(withToken: token)
        }

        switch onCancel {
        case .resume(let continuation, let result):
          continuation.resume(with: result)
        case .none:
          ()
        }
      }

    case .throwAlreadyFinished:
      throw BroadcastAsyncSequenceError.productionAlreadyFinished
    }
  }

  /// Indicate that no more values will be produced.
  ///
  /// - Parameter result: Whether the stream is finishing cleanly or because of an error.
  @inlinable
  func finish(_ result: Result<Void, Error>) {
    let action = self._state.withLockedValue { state in state.finish(result: result) }
    switch action {
    case .none:
      ()
    case .resume(let subscribers, let producers):
      subscribers.resume()
      producers.resume()
    }
  }

  // MARK: - Consumer

  /// Create a subscription to the stream.
  ///
  /// - Returns: Returns a unique subscription ID.
  @inlinable
  func subscribe() -> _BroadcastSequenceStateMachine<Element>.Subscriptions.ID {
    self._state.withLockedValue { $0.subscribe() }
  }

  /// Returns the next element for the given subscriber, if it is available.
  ///
  /// - Parameter id: The ID of the subscriber requesting the element.
  /// - Returns: The next element or `nil` if the stream has been terminated.
  @inlinable
  func nextElement(
    forSubscriber id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID
  ) async throws -> Element? {
    let onNext = self._state.withLockedValue { $0.nextElement(forSubscriber: id) }

    switch onNext {
    case .return(let returnAndProduceMore):
      returnAndProduceMore.producers.resume()
      return try returnAndProduceMore.nextResult.get()

    case .suspend:
      return try await withTaskCancellationHandler {
        return try await withCheckedThrowingContinuation { continuation in
          let onSetContinuation = self._state.withLockedValue { state in
            state.setContinuation(continuation, forSubscription: id)
          }

          switch onSetContinuation {
          case .resume(let continuation, let result):
            continuation.resume(with: result)
          case .none:
            ()
          }
        }
      } onCancel: {
        let onCancel = self._state.withLockedValue { state in
          state.cancelSubscription(withID: id)
        }

        switch onCancel {
        case .resume(let continuation, let result):
          continuation.resume(with: result)
        case .none:
          ()
        }
      }
    }
  }

  /// Returns true if it's guaranteed that the next subscriber may join and safely begin consuming
  /// elements.
  @inlinable
  var isKnownSafeForNextSubscriber: Bool {
    self._state.withLockedValue { state in
      state.nextSubscriptionIsValid
    }
  }

  /// Invalidates all active subscriptions.
  @inlinable
  func invalidateAllSubscriptions() {
    let action = self._state.withLockedValue { state in
      state.invalidateAllSubscriptions()
    }

    switch action {
    case .resume(let continuations):
      continuations.resume()
    case .none:
      ()
    }
  }
}

// MARK: - State machine

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
struct _BroadcastSequenceStateMachine<Element: Sendable>: Sendable {
  @usableFromInline
  typealias ConsumerContinuation = CheckedContinuation<Element?, Error>
  @usableFromInline
  typealias ProducerContinuation = CheckedContinuation<Void, Error>

  @usableFromInline
  struct ConsumerContinuations {
    @usableFromInline
    var continuations: _OneOrMany<ConsumerContinuation>
    @usableFromInline
    var result: Result<Element?, Error>

    @inlinable
    init(continuations: _OneOrMany<ConsumerContinuation>, result: Result<Element?, Error>) {
      self.continuations = continuations
      self.result = result
    }

    @inlinable
    func resume() {
      switch self.continuations {
      case .one(let continuation):
        continuation.resume(with: self.result)
      case .many(let continuations):
        for continuation in continuations {
          continuation.resume(with: self.result)
        }
      }
    }
  }

  @usableFromInline
  struct ProducerContinuations {
    @usableFromInline
    var continuations: [ProducerContinuation]
    @usableFromInline
    var result: Result<Void, Error>

    @inlinable
    init(continuations: [ProducerContinuation], result: Result<Void, Error>) {
      self.continuations = continuations
      self.result = result
    }

    @inlinable
    func resume() {
      for continuation in self.continuations {
        continuation.resume(with: self.result)
      }
    }
  }

  @usableFromInline
  enum State: Sendable {
    /// No subscribers and no elements have been produced.
    case initial(Initial)
    /// Subscribers exist but no elements have been produced.
    case subscribed(Subscribed)
    /// Elements have been produced, there may or may not be subscribers.
    case streaming(Streaming)
    /// No more elements will be produced. There may or may not been subscribers.
    case finished(Finished)
    /// Temporary state to avoid CoWs.
    case _modifying

    @inlinable
    init(bufferSize: Int) {
      self = .initial(Initial(bufferSize: bufferSize))
    }

    @usableFromInline
    struct Initial: Sendable {
      @usableFromInline
      let bufferSize: Int

      @inlinable
      init(bufferSize: Int) {
        self.bufferSize = bufferSize
      }
    }

    @usableFromInline
    struct Subscribed: Sendable {
      /// Active subscriptions.
      @usableFromInline
      var subscriptions: _BroadcastSequenceStateMachine<Element>.Subscriptions
      /// Subscriptions to fail and remove when they next request an element.
      @usableFromInline
      var subscriptionsToDrop: [_BroadcastSequenceStateMachine<Element>.Subscriptions.ID]

      /// The maximum size of the element buffer.
      @usableFromInline
      let bufferSize: Int

      @inlinable
      init(from state: Initial) {
        self.subscriptions = Subscriptions()
        self.subscriptionsToDrop = []
        self.bufferSize = state.bufferSize
      }

      @inlinable
      mutating func finish(result: Result<Void, Error>) -> OnFinish {
        let continuations = self.subscriptions.removeSubscribersWithContinuations()
        return .resume(
          .init(continuations: continuations, result: result.map { nil }),
          .init(continuations: [], result: .success(()))
        )
      }

      @inlinable
      mutating func next(_ id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID) -> OnNext {
        // Not streaming, so suspend or remove if the subscription should be dropped.
        guard let index = self.subscriptionsToDrop.firstIndex(of: id) else {
          return .suspend
        }

        self.subscriptionsToDrop.remove(at: index)
        return .return(.init(nextResult: .failure(BroadcastAsyncSequenceError.consumingTooSlow)))
      }

      @inlinable
      mutating func cancel(
        _ id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID
      ) -> OnCancelSubscription {
        let (_, continuation) = self.subscriptions.removeSubscriber(withID: id)
        if let continuation = continuation {
          return .resume(continuation, .failure(CancellationError()))
        } else {
          return .none
        }
      }

      @inlinable
      mutating func setContinuation(
        _ continuation: ConsumerContinuation,
        forSubscription id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID
      ) -> OnSetContinuation {
        if self.subscriptions.setContinuation(continuation, forSubscriber: id) {
          return .none
        } else {
          return .resume(continuation, .failure(CancellationError()))
        }
      }

      @inlinable
      mutating func subscribe() -> _BroadcastSequenceStateMachine<Element>.Subscriptions.ID {
        self.subscriptions.subscribe()
      }

      @inlinable
      mutating func invalidateAllSubscriptions() -> OnInvalidateAllSubscriptions {
        // Remove subscriptions with continuations, they need to be failed.
        let continuations = self.subscriptions.removeSubscribersWithContinuations()
        let consumerContinuations = ConsumerContinuations(
          continuations: continuations,
          result: .failure(BroadcastAsyncSequenceError.consumingTooSlow)
        )

        // Remove any others to be failed when they next call 'next'.
        let ids = self.subscriptions.removeAllSubscribers()
        self.subscriptionsToDrop.append(contentsOf: ids)
        return .resume(consumerContinuations)
      }

      @inlinable
      mutating func dropResources(error: BroadcastAsyncSequenceError) -> OnDropResources {
        let continuations = self.subscriptions.removeSubscribersWithContinuations()
        let consumerContinuations = ConsumerContinuations(
          continuations: continuations,
          result: .failure(error)
        )
        let producerContinuations = ProducerContinuations(continuations: [], result: .success(()))
        return .resume(consumerContinuations, producerContinuations)
      }
    }

    @usableFromInline
    struct Streaming: Sendable {
      /// A deque of elements tagged with IDs.
      @usableFromInline
      var elements: Elements
      /// The maximum size of the element buffer.
      @usableFromInline
      let bufferSize: Int

      // TODO: (optimisation) one-or-many Deque to avoid allocations in the case of a single writer
      /// Producers which have been suspended.
      @usableFromInline
      var producers: [(ProducerContinuation, Int)]
      /// The IDs of producers which have been cancelled.
      @usableFromInline
      var cancelledProducers: [Int]
      /// The next token for a producer.
      @usableFromInline
      var producerToken: Int

      /// Active subscriptions.
      @usableFromInline
      var subscriptions: _BroadcastSequenceStateMachine<Element>.Subscriptions
      /// Subscriptions to fail and remove when they next request an element.
      @usableFromInline
      var subscriptionsToDrop: [_BroadcastSequenceStateMachine<Element>.Subscriptions.ID]
      @inlinable
      init(from state: Initial) {
        self.elements = Elements()
        self.producers = []
        self.producerToken = 0
        self.cancelledProducers = []
        self.subscriptions = Subscriptions()
        self.subscriptionsToDrop = []
        self.bufferSize = state.bufferSize
      }

      @inlinable
      init(from state: Subscribed) {
        self.elements = Elements()
        self.producers = []
        self.producerToken = 0
        self.cancelledProducers = []
        self.subscriptions = state.subscriptions
        self.subscriptionsToDrop = state.subscriptionsToDrop
        self.bufferSize = state.bufferSize
      }

      @inlinable
      mutating func append(_ element: Element) -> OnYield {
        let onYield: OnYield
        self.elements.append(element)

        if self.elements.count >= self.bufferSize, let lowestID = self.elements.lowestID {
          // If the buffer is too large then:
          // - if all subscribers are equally slow suspend the producer
          // - if some subscribers are slow then remove them and the oldest value
          // - if no subscribers are slow then remove the oldest value
          let slowConsumers = self.subscriptions.subscribers(withElementID: lowestID)

          switch slowConsumers.count {
          case 0:
            if self.subscriptions.isEmpty {
              // No consumers.
              let token = self.producerToken
              self.producerToken += 1
              onYield = .suspend(token)
            } else {
              // No consumers are slow. Remove the oldest value.
              self.elements.removeFirst()
              onYield = .none
            }

          case self.subscriptions.count:
            // All consumers are slow; stop the production of new value.
            let token = self.producerToken
            self.producerToken += 1
            onYield = .suspend(token)

          default:
            // Some consumers are slow, but not all. Remove the slow consumers and drop the
            // oldest value.
            self.elements.removeFirst()
            self.subscriptions.removeAllSubscribers(in: slowConsumers)
            self.subscriptionsToDrop.append(contentsOf: slowConsumers)
            onYield = .none
          }
        } else {
          // The buffer isn't full. Take the continuations of subscriptions which have them; they
          // must be waiting for the value we just appended.
          let continuations = self.subscriptions.takeContinuations().map {
            ConsumerContinuations(continuations: $0, result: .success(element))
          }

          if let continuations = continuations {
            onYield = .resume(continuations)
          } else {
            onYield = .none
          }
        }

        return onYield
      }

      @inlinable
      mutating func next(_ id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID) -> OnNext {
        let onNext: OnNext

        // 1. Lookup the subscriber by ID to get their next offset
        // 2. If the element exists, update the element pointer and return the element
        // 3. Else if the ID is in the future, wait
        // 4. Else the ID is in the past, fail and remove the subscription.

        // Lookup the subscriber with the given ID.
        let onNextForSubscription = self.subscriptions.withMutableElementID(
          forSubscriber: id
        ) { elementID -> (OnNext, Bool) in
          let onNext: OnNext
          let removeSubscription: Bool

          // Subscriber exists; do we have the element it requires next?
          switch self.elements.lookupElement(withID: elementID) {
          case .found(let element):
            // Element exists in the buffer. Advance our element ID.
            elementID.formNext()
            onNext = .return(.init(nextResult: .success(element)))
            removeSubscription = false
          case .maybeAvailableLater:
            // Element may exist in the future.
            onNext = .suspend
            removeSubscription = false
          case .noLongerAvailable:
            // Element existed in the past but was dropped from the buffer.
            onNext = .return(
              .init(nextResult: .failure(BroadcastAsyncSequenceError.consumingTooSlow))
            )
            removeSubscription = true
          }

          return (onNext, removeSubscription)
        }

        switch onNextForSubscription {
        case .return(var resultAndResume):
          // The producer only suspends when all consumers are equally slow or there are no
          // consumers at all. The latter can't be true: this function can only be called by a
          // consumer. The former can't be true anymore because consumption isn't concurrent
          // so this consumer must be faster than the others so let the producer resume.
          //
          // Note that this doesn't mean that all other consumers will be dropped: they can continue
          // to produce until the producer provides more values.
          resultAndResume.producers = ProducerContinuations(
            continuations: self.producers.map { $0.0 },
            result: .success(())
          )
          self.producers.removeAll()
          onNext = .return(resultAndResume)

        case .suspend:
          onNext = .suspend

        case .none:
          // No subscription found, must have been dropped or already finished.
          if let index = self.subscriptionsToDrop.firstIndex(where: { $0 == id }) {
            self.subscriptionsToDrop.remove(at: index)
            onNext = .return(
              .init(nextResult: .failure(BroadcastAsyncSequenceError.consumingTooSlow))
            )
          } else {
            // Unknown subscriber, i.e. already finished.
            onNext = .return(.init(nextResult: .success(nil)))
          }
        }

        return onNext
      }

      @inlinable
      mutating func setContinuation(
        _ continuation: ConsumerContinuation,
        forSubscription id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID
      ) -> OnSetContinuation {
        if self.subscriptions.setContinuation(continuation, forSubscriber: id) {
          return .none
        } else {
          return .resume(continuation, .failure(CancellationError()))
        }
      }

      @inlinable
      mutating func cancel(
        _ id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID
      ) -> OnCancelSubscription {
        let (_, continuation) = self.subscriptions.removeSubscriber(withID: id)
        if let continuation = continuation {
          return .resume(continuation, .failure(CancellationError()))
        } else {
          return .none
        }
      }

      @inlinable
      mutating func waitToProduceMore(
        _ continuation: ProducerContinuation,
        token: Int
      ) -> OnWaitToProduceMore {
        let onWaitToProduceMore: OnWaitToProduceMore

        if self.elements.count < self.bufferSize {
          // Buffer has free space, no need to suspend.
          onWaitToProduceMore = .resume(continuation, .success(()))
        } else if let index = self.cancelledProducers.firstIndex(of: token) {
          // Producer was cancelled before suspending.
          self.cancelledProducers.remove(at: index)
          onWaitToProduceMore = .resume(continuation, .failure(CancellationError()))
        } else {
          // Store the continuation to resume later.
          self.producers.append((continuation, token))
          onWaitToProduceMore = .none
        }

        return onWaitToProduceMore
      }

      @inlinable
      mutating func cancelProducer(withToken token: Int) -> OnCancelProducer {
        guard let index = self.producers.firstIndex(where: { $0.1 == token }) else {
          self.cancelledProducers.append(token)
          return .none
        }

        let (continuation, _) = self.producers.remove(at: index)
        return .resume(continuation, .failure(CancellationError()))
      }

      @inlinable
      mutating func finish(result: Result<Void, Error>) -> OnFinish {
        let continuations = self.subscriptions.removeSubscribersWithContinuations()
        let producers = self.producers.map { $0.0 }
        self.producers.removeAll()
        return .resume(
          .init(continuations: continuations, result: result.map { nil }),
          .init(continuations: producers, result: .success(()))
        )
      }

      @inlinable
      mutating func subscribe() -> _BroadcastSequenceStateMachine<Element>.Subscriptions.ID {
        self.subscriptions.subscribe()
      }

      @inlinable
      mutating func invalidateAllSubscriptions() -> OnInvalidateAllSubscriptions {
        // Remove subscriptions with continuations, they need to be failed.
        let continuations = self.subscriptions.removeSubscribersWithContinuations()
        let consumerContinuations = ConsumerContinuations(
          continuations: continuations,
          result: .failure(BroadcastAsyncSequenceError.consumingTooSlow)
        )

        // Remove any others to be failed when they next call 'next'.
        let ids = self.subscriptions.removeAllSubscribers()
        self.subscriptionsToDrop.append(contentsOf: ids)
        return .resume(consumerContinuations)
      }

      @inlinable
      mutating func dropResources(error: BroadcastAsyncSequenceError) -> OnDropResources {
        let continuations = self.subscriptions.removeSubscribersWithContinuations()
        let consumerContinuations = ConsumerContinuations(
          continuations: continuations,
          result: .failure(error)
        )

        let producers = ProducerContinuations(
          continuations: self.producers.map { $0.0 },
          result: .failure(error)
        )

        self.producers.removeAll()

        return .resume(consumerContinuations, producers)
      }

      @inlinable
      func nextSubscriptionIsValid() -> Bool {
        return self.subscriptions.isEmpty && self.elements.lowestID == .initial
      }
    }

    @usableFromInline
    struct Finished: Sendable {
      /// A deque of elements tagged with IDs.
      @usableFromInline
      var elements: Elements

      /// Active subscriptions.
      @usableFromInline
      var subscriptions: _BroadcastSequenceStateMachine<Element>.Subscriptions
      /// Subscriptions to fail and remove when they next request an element.
      @usableFromInline
      var subscriptionsToDrop: [_BroadcastSequenceStateMachine<Element>.Subscriptions.ID]

      /// The terminating result of the sequence.
      @usableFromInline
      let result: Result<Void, Error>

      @inlinable
      init(from state: Initial, result: Result<Void, Error>) {
        self.elements = Elements()
        self.subscriptions = Subscriptions()
        self.subscriptionsToDrop = []
        self.result = result
      }

      @inlinable
      init(from state: Subscribed, result: Result<Void, Error>) {
        self.elements = Elements()
        self.subscriptions = state.subscriptions
        self.subscriptionsToDrop = []
        self.result = result
      }

      @inlinable
      init(from state: Streaming, result: Result<Void, Error>) {
        self.elements = state.elements
        self.subscriptions = state.subscriptions
        self.subscriptionsToDrop = state.subscriptionsToDrop
        self.result = result
      }

      @inlinable
      mutating func next(_ id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID) -> OnNext {
        let onNext: OnNext
        let onNextForSubscription = self.subscriptions.withMutableElementID(
          forSubscriber: id
        ) { elementID -> (OnNext, Bool) in
          let onNext: OnNext
          let removeSubscription: Bool

          switch self.elements.lookupElement(withID: elementID) {
          case .found(let element):
            elementID.formNext()
            onNext = .return(.init(nextResult: .success(element)))
            removeSubscription = false
          case .maybeAvailableLater:
            onNext = .return(.init(nextResult: self.result.map { nil }))
            removeSubscription = true
          case .noLongerAvailable:
            onNext = .return(
              .init(nextResult: .failure(BroadcastAsyncSequenceError.consumingTooSlow))
            )
            removeSubscription = true
          }

          return (onNext, removeSubscription)
        }

        switch onNextForSubscription {
        case .return(let result):
          onNext = .return(result)

        case .none:
          // No subscriber with the given ID, it was likely dropped previously.
          if let index = self.subscriptionsToDrop.firstIndex(where: { $0 == id }) {
            self.subscriptionsToDrop.remove(at: index)
            onNext = .return(
              .init(nextResult: .failure(BroadcastAsyncSequenceError.consumingTooSlow))
            )
          } else {
            // Unknown subscriber, i.e. already finished.
            onNext = .return(.init(nextResult: .success(nil)))
          }

        case .suspend:
          fatalError("Internal inconsistency")
        }

        return onNext
      }

      @inlinable
      mutating func subscribe() -> _BroadcastSequenceStateMachine<Element>.Subscriptions.ID {
        self.subscriptions.subscribe()
      }

      @inlinable
      mutating func invalidateAllSubscriptions() -> OnInvalidateAllSubscriptions {
        // Remove subscriptions with continuations, they need to be failed.
        let continuations = self.subscriptions.removeSubscribersWithContinuations()
        let consumerContinuations = ConsumerContinuations(
          continuations: continuations,
          result: .failure(BroadcastAsyncSequenceError.consumingTooSlow)
        )

        // Remove any others to be failed when they next call 'next'.
        let ids = self.subscriptions.removeAllSubscribers()
        self.subscriptionsToDrop.append(contentsOf: ids)
        return .resume(consumerContinuations)
      }

      @inlinable
      mutating func dropResources(error: BroadcastAsyncSequenceError) -> OnDropResources {
        let continuations = self.subscriptions.removeSubscribersWithContinuations()
        let consumerContinuations = ConsumerContinuations(
          continuations: continuations,
          result: .failure(error)
        )

        let producers = ProducerContinuations(continuations: [], result: .failure(error))
        return .resume(consumerContinuations, producers)
      }

      @inlinable
      func nextSubscriptionIsValid() -> Bool {
        self.elements.lowestID == .initial
      }

      @inlinable
      mutating func cancel(
        _ id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID
      ) -> OnCancelSubscription {
        let (_, continuation) = self.subscriptions.removeSubscriber(withID: id)
        if let continuation = continuation {
          return .resume(continuation, .failure(CancellationError()))
        } else {
          return .none
        }
      }
    }
  }

  @usableFromInline
  var _state: State

  @inlinable
  init(bufferSize: Int) {
    self._state = State(bufferSize: bufferSize)
  }

  @inlinable
  var nextSubscriptionIsValid: Bool {
    let isValid: Bool

    switch self._state {
    case .initial:
      isValid = true
    case .subscribed:
      isValid = true
    case .streaming(let state):
      isValid = state.nextSubscriptionIsValid()
    case .finished(let state):
      isValid = state.nextSubscriptionIsValid()
    case ._modifying:
      fatalError("Internal inconsistency")
    }

    return isValid
  }

  @usableFromInline
  enum OnInvalidateAllSubscriptions {
    case resume(ConsumerContinuations)
    case none
  }

  @inlinable
  mutating func invalidateAllSubscriptions() -> OnInvalidateAllSubscriptions {
    let onCancel: OnInvalidateAllSubscriptions

    switch self._state {
    case .initial:
      onCancel = .none

    case .subscribed(var state):
      self._state = ._modifying
      onCancel = state.invalidateAllSubscriptions()
      self._state = .subscribed(state)

    case .streaming(var state):
      self._state = ._modifying
      onCancel = state.invalidateAllSubscriptions()
      self._state = .streaming(state)

    case .finished(var state):
      self._state = ._modifying
      onCancel = state.invalidateAllSubscriptions()
      self._state = .finished(state)

    case ._modifying:
      fatalError("Internal inconsistency")
    }

    return onCancel
  }

  @usableFromInline
  enum OnYield {
    case none
    case suspend(Int)
    case resume(ConsumerContinuations)
    case throwAlreadyFinished
  }

  @inlinable
  mutating func yield(_ element: Element) -> OnYield {
    let onYield: OnYield

    switch self._state {
    case .initial(let state):
      self._state = ._modifying
      // Move to streaming.
      var state = State.Streaming(from: state)
      onYield = state.append(element)
      self._state = .streaming(state)

    case .subscribed(let state):
      self._state = ._modifying
      var state = State.Streaming(from: state)
      onYield = state.append(element)
      self._state = .streaming(state)

    case .streaming(var state):
      self._state = ._modifying
      onYield = state.append(element)
      self._state = .streaming(state)

    case .finished:
      onYield = .throwAlreadyFinished

    case ._modifying:
      fatalError("Internal inconsistency")
    }

    return onYield
  }

  @usableFromInline
  enum OnFinish {
    case none
    case resume(ConsumerContinuations, ProducerContinuations)
  }

  @inlinable
  mutating func finish(result: Result<Void, Error>) -> OnFinish {
    let onFinish: OnFinish

    switch self._state {
    case .initial(let state):
      self._state = ._modifying
      let state = State.Finished(from: state, result: result)
      self._state = .finished(state)
      onFinish = .none

    case .subscribed(var state):
      self._state = ._modifying
      onFinish = state.finish(result: result)
      self._state = .finished(State.Finished(from: state, result: result))

    case .streaming(var state):
      self._state = ._modifying
      onFinish = state.finish(result: result)
      self._state = .finished(State.Finished(from: state, result: result))

    case .finished:
      onFinish = .none

    case ._modifying:
      fatalError("Internal inconsistency")
    }

    return onFinish
  }

  @usableFromInline
  enum OnNext {
    @usableFromInline
    struct ReturnAndResumeProducers {
      @usableFromInline
      var nextResult: Result<Element?, Error>
      @usableFromInline
      var producers: ProducerContinuations

      @inlinable
      init(
        nextResult: Result<Element?, Error>,
        producers: [ProducerContinuation] = [],
        producerResult: Result<Void, Error> = .success(())
      ) {
        self.nextResult = nextResult
        self.producers = ProducerContinuations(continuations: producers, result: producerResult)
      }
    }

    case `return`(ReturnAndResumeProducers)
    case suspend
  }

  @inlinable
  mutating func nextElement(
    forSubscriber id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID
  ) -> OnNext {
    let onNext: OnNext

    switch self._state {
    case .initial:
      // No subscribers so demand isn't possible.
      fatalError("Internal inconsistency")

    case .subscribed(var state):
      self._state = ._modifying
      onNext = state.next(id)
      self._state = .subscribed(state)

    case .streaming(var state):
      self._state = ._modifying
      onNext = state.next(id)
      self._state = .streaming(state)

    case .finished(var state):
      self._state = ._modifying
      onNext = state.next(id)
      self._state = .finished(state)

    case ._modifying:
      fatalError("Internal inconsistency")
    }

    return onNext
  }

  @usableFromInline
  enum OnSetContinuation {
    case none
    case resume(ConsumerContinuation, Result<Element?, Error>)
  }

  @inlinable
  mutating func setContinuation(
    _ continuation: ConsumerContinuation,
    forSubscription id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID
  ) -> OnSetContinuation {
    let onSetContinuation: OnSetContinuation

    switch self._state {
    case .initial:
      // No subscribers so demand isn't possible.
      fatalError("Internal inconsistency")

    case .subscribed(var state):
      self._state = ._modifying
      onSetContinuation = state.setContinuation(continuation, forSubscription: id)
      self._state = .subscribed(state)

    case .streaming(var state):
      self._state = ._modifying
      onSetContinuation = state.setContinuation(continuation, forSubscription: id)
      self._state = .streaming(state)

    case .finished(let state):
      onSetContinuation = .resume(continuation, state.result.map { _ in nil })

    case ._modifying:
      // All values must have been produced, nothing to wait for.
      fatalError("Internal inconsistency")
    }

    return onSetContinuation
  }

  @usableFromInline
  enum OnCancelSubscription {
    case none
    case resume(ConsumerContinuation, Result<Element?, Error>)
  }

  @inlinable
  mutating func cancelSubscription(
    withID id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID
  ) -> OnCancelSubscription {
    let onCancel: OnCancelSubscription

    switch self._state {
    case .initial:
      // No subscribers so demand isn't possible.
      fatalError("Internal inconsistency")

    case .subscribed(var state):
      self._state = ._modifying
      onCancel = state.cancel(id)
      self._state = .subscribed(state)

    case .streaming(var state):
      self._state = ._modifying
      onCancel = state.cancel(id)
      self._state = .streaming(state)

    case .finished(var state):
      self._state = ._modifying
      onCancel = state.cancel(id)
      self._state = .finished(state)

    case ._modifying:
      // All values must have been produced, nothing to wait for.
      fatalError("Internal inconsistency")
    }

    return onCancel
  }

  @usableFromInline
  enum OnSubscribe {
    case subscribed(_BroadcastSequenceStateMachine<Element>.Subscriptions.ID)
  }

  @inlinable
  mutating func subscribe() -> _BroadcastSequenceStateMachine<Element>.Subscriptions.ID {
    let id: _BroadcastSequenceStateMachine<Element>.Subscriptions.ID

    switch self._state {
    case .initial(let state):
      self._state = ._modifying
      var state = State.Subscribed(from: state)
      id = state.subscribe()
      self._state = .subscribed(state)

    case .subscribed(var state):
      self._state = ._modifying
      id = state.subscribe()
      self._state = .subscribed(state)

    case .streaming(var state):
      self._state = ._modifying
      id = state.subscribe()
      self._state = .streaming(state)

    case .finished(var state):
      self._state = ._modifying
      id = state.subscribe()
      self._state = .finished(state)

    case ._modifying:
      fatalError("Internal inconsistency")
    }

    return id
  }

  @usableFromInline
  enum OnWaitToProduceMore {
    case none
    case resume(ProducerContinuation, Result<Void, Error>)
  }

  @inlinable
  mutating func waitToProduceMore(
    continuation: ProducerContinuation,
    token: Int
  ) -> OnWaitToProduceMore {
    let onWaitToProduceMore: OnWaitToProduceMore

    switch self._state {
    case .initial, .subscribed:
      // Nothing produced yet, so no reason have to wait to produce.
      fatalError("Internal inconsistency")

    case .streaming(var state):
      self._state = ._modifying
      onWaitToProduceMore = state.waitToProduceMore(continuation, token: token)
      self._state = .streaming(state)

    case .finished:
      onWaitToProduceMore = .resume(continuation, .success(()))

    case ._modifying:
      fatalError("Internal inconsistency")
    }

    return onWaitToProduceMore
  }

  @usableFromInline
  typealias OnCancelProducer = OnWaitToProduceMore

  @inlinable
  mutating func cancelProducer(withToken token: Int) -> OnCancelProducer {
    let onCancelProducer: OnCancelProducer

    switch self._state {
    case .initial, .subscribed:
      // Nothing produced yet, so no reason have to wait to produce.
      fatalError("Internal inconsistency")

    case .streaming(var state):
      self._state = ._modifying
      onCancelProducer = state.cancelProducer(withToken: token)
      self._state = .streaming(state)

    case .finished:
      // No producers to cancel; do nothing.
      onCancelProducer = .none

    case ._modifying:
      fatalError("Internal inconsistency")
    }

    return onCancelProducer
  }

  @usableFromInline
  enum OnDropResources {
    case none
    case resume(ConsumerContinuations, ProducerContinuations)
  }

  @inlinable
  mutating func dropResources() -> OnDropResources {
    let error = BroadcastAsyncSequenceError.productionAlreadyFinished
    let onDrop: OnDropResources

    switch self._state {
    case .initial(let state):
      self._state = ._modifying
      onDrop = .none
      self._state = .finished(State.Finished(from: state, result: .failure(error)))

    case .subscribed(var state):
      self._state = ._modifying
      onDrop = state.dropResources(error: error)
      self._state = .finished(State.Finished(from: state, result: .failure(error)))

    case .streaming(var state):
      self._state = ._modifying
      onDrop = state.dropResources(error: error)
      self._state = .finished(State.Finished(from: state, result: .failure(error)))

    case .finished(var state):
      self._state = ._modifying
      onDrop = state.dropResources(error: error)
      self._state = .finished(state)

    case ._modifying:
      fatalError("Internal inconsistency")
    }

    return onDrop
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension _BroadcastSequenceStateMachine {
  /// A collection of elements tagged with an identifier.
  ///
  /// Identifiers are assigned when elements are added to the collection and are monotonically
  /// increasing. If element 'A' is added before element 'B' then 'A' will have a lower ID than 'B'.
  @usableFromInline
  struct Elements: Sendable {
    /// The ID of an element
    @usableFromInline
    struct ID: Hashable, Sendable, Comparable, Strideable {
      @usableFromInline
      private(set) var rawValue: Int

      @usableFromInline
      static var initial: Self {
        ID(id: 0)
      }

      private init(id: Int) {
        self.rawValue = id
      }

      @inlinable
      mutating func formNext() {
        self.rawValue += 1
      }

      @inlinable
      func next() -> Self {
        var copy = self
        copy.formNext()
        return copy
      }

      @inlinable
      func distance(to other: Self) -> Int {
        other.rawValue - self.rawValue
      }

      @inlinable
      func advanced(by n: Int) -> Self {
        var copy = self
        copy.rawValue += n
        return copy
      }

      @inlinable
      static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
      }
    }

    @usableFromInline
    struct _IdentifiableElement: Sendable {
      @usableFromInline
      var element: Element
      @usableFromInline
      var id: ID

      @inlinable
      init(element: Element, id: ID) {
        self.element = element
        self.id = id
      }
    }

    @usableFromInline
    var _elements: Deque<_IdentifiableElement>
    @usableFromInline
    var _nextID: ID

    @inlinable
    init() {
      self._nextID = .initial
      self._elements = []
    }

    @inlinable
    mutating func nextElementID() -> ID {
      let id = self._nextID
      self._nextID.formNext()
      return id
    }

    /// The highest ID of the stored elements; `nil` if there are no elements.
    @inlinable
    var highestID: ID? { self._elements.last?.id }

    /// The lowest ID of the stored elements; `nil` if there are no elements.
    @inlinable
    var lowestID: ID? { self._elements.first?.id }

    /// The number of stored elements.
    @inlinable
    var count: Int { self._elements.count }

    /// Whether there are no stored elements.
    @inlinable
    var isEmpty: Bool { self._elements.isEmpty }

    /// Appends an element to the collection.
    @inlinable
    mutating func append(_ element: Element) {
      self._elements.append(_IdentifiableElement(element: element, id: self.nextElementID()))
    }

    /// Removes the first element from the collection.
    @discardableResult
    @inlinable
    mutating func removeFirst() -> Element {
      let removed = self._elements.removeFirst()
      return removed.element
    }

    @usableFromInline
    enum ElementLookup {
      /// The element was found in the collection.
      case found(Element)
      /// The element isn't in the collection, but it could be in the future.
      case maybeAvailableLater
      /// The element was in the collection, but is no longer available.
      case noLongerAvailable
    }

    /// Lookup the element with the given ID.
    ///
    /// - Parameter id: The ID of the element to lookup.
    @inlinable
    mutating func lookupElement(withID id: ID) -> ElementLookup {
      guard let low = self.lowestID, let high = self.highestID else {
        // Must be empty.
        return id >= self._nextID ? .maybeAvailableLater : .noLongerAvailable
      }
      assert(low <= high)

      let lookup: ElementLookup

      if id < low {
        lookup = .noLongerAvailable
      } else if id > high {
        lookup = .maybeAvailableLater
      } else {
        // IDs are monotonically increasing. If the buffer contains the tag we can use it to index
        // into the deque by looking at the offsets.
        let offset = low.distance(to: id)
        let index = self._elements.startIndex.advanced(by: offset)
        lookup = .found(self._elements[index].element)
      }

      return lookup
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension _BroadcastSequenceStateMachine {
  /// A collection of subscriptions.
  @usableFromInline
  struct Subscriptions: Sendable {
    @usableFromInline
    struct ID: Hashable, Sendable {
      @usableFromInline
      private(set) var rawValue: Int

      @inlinable
      init() {
        self.rawValue = 0
      }

      @inlinable
      mutating func formNext() {
        self.rawValue += 1
      }

      @inlinable
      func next() -> Self {
        var copy = self
        copy.formNext()
        return copy
      }
    }

    @usableFromInline
    struct _Subscriber: Sendable {
      /// The ID of the subscriber.
      @usableFromInline
      var id: ID

      /// The ID of the next element the subscriber will consume.
      @usableFromInline
      var nextElementID: _BroadcastSequenceStateMachine<Element>.Elements.ID

      /// A continuation which which will be resumed when the next element becomes available.
      @usableFromInline
      var continuation: ConsumerContinuation?

      @inlinable
      init(
        id: ID,
        nextElementID: _BroadcastSequenceStateMachine<Element>.Elements.ID,
        continuation: ConsumerContinuation? = nil
      ) {
        self.id = id
        self.nextElementID = nextElementID
        self.continuation = continuation
      }

      /// Returns and sets the continuation to `nil` if one exists.
      ///
      /// The next element ID is advanced if a contination exists.
      ///
      /// - Returns: The continuation, if one existed.
      @inlinable
      mutating func takeContinuation() -> ConsumerContinuation? {
        guard let continuation = self.continuation else { return nil }
        self.continuation = nil
        self.nextElementID.formNext()
        return continuation
      }
    }

    @usableFromInline
    var _subscribers: [_Subscriber]
    @usableFromInline
    var _nextSubscriberID: ID

    @inlinable
    init() {
      self._subscribers = []
      self._nextSubscriberID = ID()
    }

    /// Returns the number of subscribers.
    @inlinable
    var count: Int { self._subscribers.count }

    /// Returns whether the collection is empty.
    @inlinable
    var isEmpty: Bool { self._subscribers.isEmpty }

    /// Adds a new subscriber and returns its unique ID.
    ///
    /// - Returns: The ID of the new subscriber.
    @inlinable
    mutating func subscribe() -> ID {
      let id = self._nextSubscriberID
      self._nextSubscriberID.formNext()
      self._subscribers.append(_Subscriber(id: id, nextElementID: .initial))
      return id
    }

    /// Provides mutable access to the element ID of the given subscriber, if it exists.
    ///
    /// - Parameters:
    ///   - id: The ID of the subscriber.
    ///   - body: A closure to mutate the element ID of the subscriber which returns the result and
    ///      a boolean indicating whether the subscriber should be removed.
    /// - Returns: The result returned from the closure or `nil` if no subscriber exists with the
    ///     given ID.
    @inlinable
    mutating func withMutableElementID<R>(
      forSubscriber id: ID,
      _ body: (
        inout _BroadcastSequenceStateMachine<Element>.Elements.ID
      ) -> (result: R, removeSubscription: Bool)
    ) -> R? {
      guard let index = self._subscribers.firstIndex(where: { $0.id == id }) else { return nil }
      let (result, removeSubscription) = body(&self._subscribers[index].nextElementID)
      if removeSubscription {
        self._subscribers.remove(at: index)
      }
      return result
    }

    /// Sets the continuation for the subscription with the given ID.
    /// - Parameters:
    ///   - continuation: The continuation to set.
    ///   - id: The ID of the subscriber.
    /// - Returns: A boolean indicating whether the continuation was set or not.
    @inlinable
    mutating func setContinuation(
      _ continuation: ConsumerContinuation,
      forSubscriber id: ID
    ) -> Bool {
      guard let index = self._subscribers.firstIndex(where: { $0.id == id }) else {
        return false
      }

      assert(self._subscribers[index].continuation == nil)
      self._subscribers[index].continuation = continuation
      return true
    }

    /// Returns an array of subscriber IDs which are whose next element ID is `id`.
    @inlinable
    func subscribers(
      withElementID id: _BroadcastSequenceStateMachine<Element>.Elements.ID
    ) -> [ID] {
      return self._subscribers.filter {
        $0.nextElementID == id
      }.map {
        $0.id
      }
    }

    /// Removes the subscriber with the given ID.
    /// - Parameter id: The ID of the subscriber to remove.
    /// - Returns: A tuple indicating whether a subscriber was removed and any continuation
    ///     associated with the subscriber.
    @inlinable
    mutating func removeSubscriber(withID id: ID) -> (Bool, ConsumerContinuation?) {
      guard let index = self._subscribers.firstIndex(where: { $0.id == id }) else {
        return (false, nil)
      }

      let continuation = self._subscribers[index].continuation
      self._subscribers.remove(at: index)
      return (true, continuation)
    }

    /// Remove all subscribers in the given array of IDs.
    @inlinable
    mutating func removeAllSubscribers(in idsToRemove: [ID]) {
      self._subscribers.removeAll {
        idsToRemove.contains($0.id)
      }
    }

    /// Remove all subscribers and return their IDs.
    @inlinable
    mutating func removeAllSubscribers() -> [ID] {
      let subscribers = self._subscribers.map { $0.id }
      self._subscribers.removeAll()
      return subscribers
    }

    /// Returns any continuations set on subscribers, unsetting at the same time.
    @inlinable
    mutating func takeContinuations() -> _OneOrMany<ConsumerContinuation>? {
      // Avoid allocs if there's only one subscriber.
      let count = self._countPendingContinuations()
      let result: _OneOrMany<ConsumerContinuation>?

      switch count {
      case 0:
        result = nil

      case 1:
        let index = self._subscribers.firstIndex(where: { $0.continuation != nil })!
        let continuation = self._subscribers[index].takeContinuation()!
        result = .one(continuation)

      default:
        var continuations = [ConsumerContinuation]()
        continuations.reserveCapacity(count)

        for index in self._subscribers.indices {
          if let continuation = self._subscribers[index].takeContinuation() {
            continuations.append(continuation)
          }
        }

        result = .many(continuations)
      }

      return result
    }

    /// Removes all subscribers which have continuations and return their continuations.
    @inlinable
    mutating func removeSubscribersWithContinuations() -> _OneOrMany<ConsumerContinuation> {
      // Avoid allocs if there's only one subscriber.
      let count = self._countPendingContinuations()
      let result: _OneOrMany<ConsumerContinuation>

      switch count {
      case 0:
        result = .many([])

      case 1:
        let index = self._subscribers.firstIndex(where: { $0.continuation != nil })!
        let subscription = self._subscribers.remove(at: index)
        result = .one(subscription.continuation!)

      default:
        var continuations = [ConsumerContinuation]()
        continuations.reserveCapacity(count)
        var removable = [ID]()
        removable.reserveCapacity(count)

        for subscription in self._subscribers {
          if let continuation = subscription.continuation {
            continuations.append(continuation)
            removable.append(subscription.id)
          }
        }

        self._subscribers.removeAll {
          removable.contains($0.id)
        }

        result = .many(continuations)
      }

      return result
    }

    @inlinable
    func _countPendingContinuations() -> Int {
      return self._subscribers.reduce(into: 0) { count, subscription in
        if subscription.continuation != nil {
          count += 1
        }
      }
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension _BroadcastSequenceStateMachine {
  // TODO: tiny array
  @usableFromInline
  enum _OneOrMany<Value> {
    case one(Value)
    case many([Value])
  }
}
