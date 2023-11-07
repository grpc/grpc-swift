/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIOCore

/// Provides keepalive pings.
///
/// The defaults are determined by the gRPC keepalive
/// [documentation] (https://github.com/grpc/grpc/blob/master/doc/keepalive.md).
public struct ClientConnectionKeepalive: Hashable, Sendable {
  private func checkInvariants(line: UInt = #line) {
    precondition(self.timeout < self.interval, "'timeout' must be less than 'interval'", line: line)
  }

  /// The amount of time to wait before sending a keepalive ping.
  public var interval: TimeAmount {
    didSet { self.checkInvariants() }
  }

  /// The amount of time to wait for an acknowledgment.
  /// If it does not receive an acknowledgment within this time, it will close the connection
  /// This value must be less than ``interval``.
  public var timeout: TimeAmount {
    didSet { self.checkInvariants() }
  }

  /// Send keepalive pings even if there are no calls in flight.
  public var permitWithoutCalls: Bool

  /// Maximum number of pings that can be sent when there is no data/header frame to be sent.
  public var maximumPingsWithoutData: UInt

  /// If there are no data/header frames being received:
  /// The minimum amount of time to wait between successive pings.
  public var minimumSentPingIntervalWithoutData: TimeAmount

  public init(
    interval: TimeAmount = .nanoseconds(Int64.max),
    timeout: TimeAmount = .seconds(20),
    permitWithoutCalls: Bool = false,
    maximumPingsWithoutData: UInt = 2,
    minimumSentPingIntervalWithoutData: TimeAmount = .minutes(5)
  ) {
    self.interval = interval
    self.timeout = timeout
    self.permitWithoutCalls = permitWithoutCalls
    self.maximumPingsWithoutData = maximumPingsWithoutData
    self.minimumSentPingIntervalWithoutData = minimumSentPingIntervalWithoutData
    self.checkInvariants()
  }
}

extension ClientConnectionKeepalive {
  /// Applies jitter to the ``interval``.
  ///
  /// The current ``interval`` will be adjusted by no more than `maxJitter` in either direction,
  /// that is the ``interval`` may increase or decrease by no more than `maxJitter`. As
  /// the ``timeout`` must be strictly less than the ``interval``, the lower range of the jittered
  /// interval is clamped to `max(interval - maxJitter, timeout + .nanoseconds(1)))`.
  ///
  /// - Parameter maxJitter: The maximum amount of jitter to apply to the ``interval``, which may
  ///     be applied in either direction.
  public mutating func jitterInterval(byAtMost maxJitter: TimeAmount) {
    // The interval must be larger than the timeout so clamp the lower bound to be greater than
    // the timeout.
    let lowerBound = max(self.interval - maxJitter, self.timeout + .nanoseconds(1))
    let upperBound = self.interval + maxJitter
    self.interval = .nanoseconds(.random(in: lowerBound.nanoseconds ... upperBound.nanoseconds))
  }

  /// Returns a new ``ClientConnectionKeepalive`` with a jittered ``interval``.
  ///
  /// See also ``jitterInterval(byAtMost:)``.
  ///
  /// - Parameter maxJitter: The maximum amount of jitter to apply to the ``interval``, which may
  ///     be applied in either direction.
  /// - Returns: A new ``ClientConnectionKeepalive``.
  public func jitteringInterval(byAtMost maxJitter: TimeAmount) -> Self {
    var copy = self
    copy.jitterInterval(byAtMost: maxJitter)
    return copy
  }
}

public struct ServerConnectionKeepalive: Hashable {
  private func checkInvariants(line: UInt = #line) {
    precondition(self.timeout < self.interval, "'timeout' must be less than 'interval'", line: line)
  }

  /// The amount of time to wait before sending a keepalive ping.
  public var interval: TimeAmount {
    didSet { self.checkInvariants() }
  }

  /// The amount of time to wait for an acknowledgment.
  /// If it does not receive an acknowledgment within this time, it will close the connection
  /// This value must be less than ``interval``.
  public var timeout: TimeAmount {
    didSet { self.checkInvariants() }
  }

  /// Send keepalive pings even if there are no calls in flight.
  public var permitWithoutCalls: Bool

  /// Maximum number of pings that can be sent when there is no data/header frame to be sent.
  public var maximumPingsWithoutData: UInt

  /// If there are no data/header frames being received:
  /// The minimum amount of time to wait between successive pings.
  public var minimumSentPingIntervalWithoutData: TimeAmount

  /// If there are no data/header frames being sent:
  /// The minimum amount of time expected between receiving successive pings.
  /// If the time between successive pings is less than this value, then the ping will be considered a bad ping from the peer.
  /// Such a ping counts as a "ping strike".
  public var minimumReceivedPingIntervalWithoutData: TimeAmount

  /// Maximum number of bad pings that the server will tolerate before sending an HTTP2 GOAWAY frame and closing the connection.
  /// Setting it to `0` allows the server to accept any number of bad pings.
  public var maximumPingStrikes: UInt

  public init(
    interval: TimeAmount = .hours(2),
    timeout: TimeAmount = .seconds(20),
    permitWithoutCalls: Bool = false,
    maximumPingsWithoutData: UInt = 2,
    minimumSentPingIntervalWithoutData: TimeAmount = .minutes(5),
    minimumReceivedPingIntervalWithoutData: TimeAmount = .minutes(5),
    maximumPingStrikes: UInt = 2
  ) {
    self.interval = interval
    self.timeout = timeout
    self.permitWithoutCalls = permitWithoutCalls
    self.maximumPingsWithoutData = maximumPingsWithoutData
    self.minimumSentPingIntervalWithoutData = minimumSentPingIntervalWithoutData
    self.minimumReceivedPingIntervalWithoutData = minimumReceivedPingIntervalWithoutData
    self.maximumPingStrikes = maximumPingStrikes
    self.checkInvariants()
  }
}

extension ServerConnectionKeepalive {
  /// Applies jitter to the ``interval``.
  ///
  /// The current ``interval`` will be adjusted by no more than `maxJitter` in either direction,
  /// that is the ``interval`` may increase or decrease by no more than `maxJitter`. As
  /// the ``timeout`` must be strictly less than the ``interval``, the lower range of the jittered
  /// interval is clamped to `max(interval - maxJitter, timeout + .nanoseconds(1)))`.
  ///
  /// - Parameter maxJitter: The maximum amount of jitter to apply to the ``interval``, which may
  ///     be applied in either direction.
  public mutating func jitterInterval(byAtMost maxJitter: TimeAmount) {
    // The interval must be larger than the timeout so clamp the lower bound to be greater than
    // the timeout.
    let lowerBound = max(self.interval - maxJitter, self.timeout + .nanoseconds(1))
    let upperBound = self.interval + maxJitter
    self.interval = .nanoseconds(.random(in: lowerBound.nanoseconds ... upperBound.nanoseconds))
  }

  /// Returns a new ``ClientConnectionKeepalive`` with a jittered ``interval``.
  ///
  /// See also ``jitterInterval(byAtMost:)``.
  ///
  /// - Parameter maxJitter: The maximum amount of jitter to apply to the ``interval``, which may
  ///     be applied in either direction.
  /// - Returns: A new ``ClientConnectionKeepalive``.
  public func jitteringInterval(byAtMost maxJitter: TimeAmount) -> Self {
    var copy = self
    copy.jitterInterval(byAtMost: maxJitter)
    return copy
  }
}
