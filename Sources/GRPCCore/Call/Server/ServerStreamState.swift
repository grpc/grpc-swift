/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

import Synchronization

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct ServerStreamState: Sendable {
  /// Returns whether the RPC has been cancelled.
  ///
  /// - SeeAlso: ``ServerStreamEvent/rpcCancelled``.
  public var isRPCCancelled: Bool {
    self.events.isRPCCancelled
  }

  /// Events which can happen to the underlying stream the RPC is being run on.
  public let events: Events

  private init(events: Events) {
    self.events = events
  }

  public static func makeState() -> (streamState: Self, eventContinuation: Events.Continuation) {
    let events = Events()
    return (ServerStreamState(events: events), eventContinuation: events.continuation)
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ServerStreamState {
  /// An `AsyncSequence` of events which can happen to the stream.
  ///
  /// Each event will be delivered at most once.
  ///
  /// - Note: This sequence supports _multiple_ concurrent iterators.
  public struct Events {
    private let storage: Storage
    @usableFromInline
    internal let continuation: Continuation
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ServerStreamState.Events: AsyncSequence, Sendable {
  public typealias Element = ServerStreamEvent
  public typealias Failure = Never

  init() {
    self.storage = Storage()
    self.continuation = Continuation(storage: self.storage)
  }

  fileprivate var isRPCCancelled: Bool {
    self.storage.eventSet(contains: .rpcCancelled)
  }

  public func makeAsyncIterator() -> AsyncIterator {
    let streamEvents = AsyncStream.makeStream(of: ServerStreamEvent.self)
    self.storage.registerContinuation(streamEvents.continuation)
    return AsyncIterator(iterator: streamEvents.stream.makeAsyncIterator())
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    private var iterator: AsyncStream<ServerStreamEvent>.AsyncIterator

    fileprivate init(iterator: AsyncStream<ServerStreamEvent>.AsyncIterator) {
      self.iterator = iterator
    }

    public mutating func next() async throws(Never) -> ServerStreamEvent? {
      await self.next(isolation: nil)
    }

    public mutating func next(
      isolation actor: isolated (any Actor)?
    ) async throws(Never) -> ServerStreamEvent? {
      return await self.iterator.next(isolation: actor)
    }
  }

  public struct Continuation: Sendable {
    private let storage: Storage

    init(storage: Storage) {
      self.storage = storage
    }

    /// Yield an event to the stream.
    ///
    /// - Important: Events are only delivered once. If the event has already been yielded
    ///   then attempting to yield it again is a no-op.
    /// - Parameter event: The event to yield.
    public func yield(_ event: ServerStreamEvent) {
      self.storage.yield(event)
    }

    /// Indicate that no more events will be delivered.
    public func finish() {
      self.storage.finish()
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ServerStreamState.Events {
  final class Storage: Sendable {
    private let state: Mutex<State>

    init() {
      self.state = Mutex(State())
    }

    func eventSet(contains event: ServerStreamEvent) -> Bool {
      self.state.withLock { $0.eventSet.contains(EventSet(event)) }
    }

    func registerContinuation(_ continuation: AsyncStream<ServerStreamEvent>.Continuation) {
      self.state.withLock {
        let events = $0.registerContinuation(continuation)

        if events.contains(.rpcCancelled) {
          continuation.yield(.rpcCancelled)
        }

        if events.contains(.finished) {
          continuation.finish()
        }
      }
    }

    func yield(_ event: ServerStreamEvent) {
      self.state.withLock {
        for continuation in $0.publishStreamEvent(event) {
          continuation.yield(event)
        }
      }
    }

    func finish() {
      self.state.withLock {
        for continuation in $0.finish() {
          continuation.finish()
        }
      }
    }
  }

  private struct EventSet: OptionSet, Hashable, Sendable {
    var rawValue: UInt8

    init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    init(_ event: ServerStreamEvent) {
      switch event.value {
      case .rpcCancelled:
        self = .rpcCancelled
      }
    }

    static let finished = EventSet(rawValue: 1 << 0)
    static let rpcCancelled = EventSet(rawValue: 1 << 1)
  }

  private struct State: Sendable {
    private(set) var eventSet: EventSet
    private var continuations: [AsyncStream<ServerStreamEvent>.Continuation]

    init() {
      self.eventSet = EventSet()
      self.continuations = []
    }

    mutating func registerContinuation(
      _ continuation: AsyncStream<ServerStreamEvent>.Continuation
    ) -> EventSet {
      if !self.eventSet.contains(.finished) {
        self.continuations.append(continuation)
      }

      return self.eventSet
    }

    mutating func publishStreamEvent(
      _ streamEvent: ServerStreamEvent
    ) -> [AsyncStream<ServerStreamEvent>.Continuation] {
      if self.eventSet.contains(.finished) {
        return []
      } else {
        let (inserted, _) = self.eventSet.insert(EventSet(streamEvent))
        return inserted ? self.continuations : []
      }
    }

    mutating func finish() -> [AsyncStream<ServerStreamEvent>.Continuation] {
      let (inserted, _) = self.eventSet.insert(.finished)
      return inserted ? self.continuations : []
    }
  }
}
