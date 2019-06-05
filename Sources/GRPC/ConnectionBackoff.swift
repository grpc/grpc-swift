/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation

/// Provides backoff timeouts for making a connection.
///
/// This algorithm and defaults are determined by the gRPC connection backoff
/// [documentation](https://github.com/grpc/grpc/blob/master/doc/connection-backoff.md).
public struct ConnectionBackoff: Sequence {
  public typealias Iterator = ConnectionBackoffIterator

  /// The initial backoff in seconds.
  public var initialBackoff: TimeInterval

  /// The maximum backoff in seconds. Note that the backoff is _before_ jitter has been applied,
  /// this means that in practice the maximum backoff can be larger than this value.
  public var maximumBackoff: TimeInterval

  /// The backoff multiplier.
  public var multiplier: Double

  /// Backoff jitter; should be between 0 and 1.
  public var jitter: Double

  /// The minimum amount of time in seconds to try connecting.
  public var minimumConnectionTimeout: TimeInterval

  /// Creates a `ConnectionBackoff`.
  ///
  /// - Parameters:
  ///   - initialBackoff: Initial backoff in seconds, defaults to 1.0.
  ///   - maximumBackoff: Maximum backoff in seconds (prior to adding jitter), defaults to 120.0.
  ///   - multiplier: Backoff multiplier, defaults to 1.6.
  ///   - jitter: Backoff jitter, defaults to 0.2.
  ///   - minimumConnectionTimeout: Minimum connection timeout in seconds, defaults to 20.0.
  public init(
    initialBackoff: TimeInterval = 1.0,
    maximumBackoff: TimeInterval = 120.0,
    multiplier: Double = 1.6,
    jitter: Double = 0.2,
    minimumConnectionTimeout: TimeInterval = 20.0
  ) {
    self.initialBackoff = initialBackoff
    self.maximumBackoff = maximumBackoff
    self.multiplier = multiplier
    self.jitter = jitter
    self.minimumConnectionTimeout = minimumConnectionTimeout
  }

  public func makeIterator() -> ConnectionBackoff.Iterator {
    return Iterator(connectionBackoff: self)
  }
}

/// An iterator for `ConnectionBackoff`.
public class ConnectionBackoffIterator: IteratorProtocol {
  public typealias Element = (timeout: TimeInterval, backoff: TimeInterval)

  /// Creates a new connection backoff iterator with the given configuration.
  public init(connectionBackoff: ConnectionBackoff) {
    self.connectionBackoff = connectionBackoff
    self.unjitteredBackoff = connectionBackoff.initialBackoff

    // Generate the current and next elements. The first entry has no backoff (i.e. start the first
    // attempt immediately). The second entry is not jittered.
    //
    // We generate `nextElement` before `currentElement` as we need to initialize `productionState`
    // before can call `makeElement`.
    if connectionBackoff.initialBackoff < connectionBackoff.maximumBackoff {
      self.productionState = .producing
      self.nextElement = self.makeElement(backoff: connectionBackoff.initialBackoff)
    } else {
      self.productionState = .stopped
      self.nextElement = self.makeElement(backoff: connectionBackoff.maximumBackoff)
    }

    self.currentElement = self.makeElement(backoff: 0.0)
  }

  /// The configuration being used.
  private let connectionBackoff: ConnectionBackoff

  /// The backoff in seconds, without jitter.
  private var unjitteredBackoff: TimeInterval

  /// The state of production.
  private var productionState: ProductionState

  /// The current timeout and backoff waiting to be returned. This will become `nil` when we run
  /// out of values to return.
  private var currentElement: Element?

  /// The next timeout and backoff to be returned.
  private var nextElement: Element?

  // The current state of production.
  private enum ProductionState {
    // Continue to produce values.
    case producing
    // No more values will be produced, but some may already exist which may be returned.
    case stopped
  }

  /// Returns the next pair connection timeout and backoff (in that order) to use should the
  /// connection attempt fail.
  ///
  /// The iterator will stop producing values _after_ the unjittered backoff is greater than or
  /// equal to the maximum backoff set in the configuration used to create this iterator.
  public func next() -> Element? {
    guard let current = self.currentElement else {
      return nil
    }

    self.currentElement = self.nextElement

    switch self.productionState {
    case .producing:
      self.nextElement = self.makeNextElement()
    case .stopped:
      self.nextElement = nil
    }

    return current
  }

  /// Produces the next element to return. This must only be called when then iterator is producing
  /// values.
  private func makeNextElement() -> Element {
    precondition(self.productionState == .producing, "invalid state \(self.productionState)")
    self.unjitteredBackoff = self.unjitteredBackoff * self.connectionBackoff.multiplier

    // If the backoff is too big before jitter, clamp it to the maximum backoff and set out
    // production state to `.stopped` so that this is the final value.
    if self.unjitteredBackoff >= self.connectionBackoff.maximumBackoff {
      self.unjitteredBackoff = self.connectionBackoff.maximumBackoff
      self.productionState = .stopped
    }

    let backoff = self.jittered(value: self.unjitteredBackoff)
    return self.makeElement(backoff: backoff)
  }

  /// Make a timeout-backoff pair from the given backoff. The timeout is the `max` of the backoff
  /// and `connectionBackoff.minimumConnectionTimeout`.
  private func makeElement(backoff: TimeInterval) -> Element {
    let timeout = max(backoff, self.connectionBackoff.minimumConnectionTimeout)
    return (timeout, backoff)
  }

  /// Adds 'jitter' to the given value.
  private func jittered(value: TimeInterval) -> TimeInterval {
    let lower = -self.connectionBackoff.jitter * value
    let upper = self.connectionBackoff.jitter * value
    return value + TimeInterval.random(in: lower...upper)
  }
}
