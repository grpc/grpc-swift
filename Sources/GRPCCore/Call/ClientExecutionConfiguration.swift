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

/// Configuration values for executing an RPC.
public struct ClientExecutionConfiguration: Hashable, Sendable {
  /// The default timeout for the RPC.
  ///
  /// If no reply is received in the specified amount of time the request is aborted
  /// with an ``RPCError`` with code ``RPCError/Code/deadlineExceeded``.
  ///
  /// The actual deadline used will be the minimum of the value specified here
  /// and the value set by the application by the client API. If either one isn't set
  /// then the other value is used. If neither is set then the request has no deadline.
  ///
  /// The timeout applies to the overall execution of an RPC. If, for example, a retry
  /// policy is set then the timeout begins when the first attempt is started and _isn't_ reset
  /// when subsequent attempts start.
  public var timeout: RPCDuration?

  /// The policy determining how many times, and when, the RPC is executed.
  ///
  /// There are two policy types:
  /// 1. Retry
  /// 2. Hedging
  ///
  /// The retry policy allows an RPC to be retried a limited number of times if the RPC
  /// fails with one of the configured set of status codes. RPCs are only retried if they
  /// fail immediately, that is, the first response part received from the server is a
  /// status code.
  ///
  /// The hedging policy allows an RPC to be executed multiple times concurrently. Typically
  /// each execution will be staggered by some delay. The first successful response will be
  /// reported to the client. Hedging is only suitable for idempotent RPCs.
  public var executionPolicy: ExecutionPolicy?

  public init(
    executionPolicy: ExecutionPolicy?,
    timeout: RPCDuration?
  ) {
    self.executionPolicy = executionPolicy
    self.timeout = timeout
  }

  public init(
    retryPolicy: RetryPolicy,
    timeout: RPCDuration? = nil
  ) {
    self.executionPolicy = .retry(retryPolicy)
    self.timeout = timeout
  }

  public init(
    hedgingPolicy: HedgingPolicy,
    timeout: RPCDuration? = nil
  ) {
    self.executionPolicy = .hedge(hedgingPolicy)
    self.timeout = timeout
  }
}

extension ClientExecutionConfiguration {
  /// The execution policy for an RPC.
  public enum ExecutionPolicy: Hashable, Sendable {
    /// Policy for retrying an RPC.
    ///
    /// See ``RetryPolicy`` for more details.
    case retry(RetryPolicy)

    /// Policy for hedging an RPC.
    ///
    /// See ``HedgingPolicy`` for more details.
    case hedge(HedgingPolicy)
  }
}

/// Policy for retrying an RPC.
///
/// gRPC retries RPCs when the first response from the server is a status code which matches
/// one of the configured retryable status codes. If the server begins processing the RPC and
/// first responds with metadata and later responds with a retryable status code then the RPC
/// won't be retried.
///
/// Execution attempts are limited by ``maxAttempts`` which includes the original attempt. The
/// maximum number of attempts is limited to five.
///
/// Subsequent attempts are executed after some delay. The first _retry_, or second attempt, will
/// be started after a randomly chosen delay between zero and ``initialBackoff``. More generally,
/// the nth retry will happen after a randomly chosen delay between zero
/// and `min(initialBackoff * backoffMultiplier^(n-1), maxBackoff)`.
///
/// For more information see [gRFC A6 Client
/// Retries](https://github.com/grpc/proposal/blob/master/A6-client-retries.md).
public struct RetryPolicy: Hashable, Sendable {
  /// The maximum number of RPC attempts, including the original attempt.
  ///
  /// Must be greater than one, values greater than five are treated as five.
  public var maxAttempts: Int {
    didSet { self.maxAttempts = validateMaxAttempts(self.maxAttempts) }
  }

  /// The initial backoff duration.
  ///
  /// The initial retry will occur after a random amount of time up to this value. Must be
  /// greater than zero.
  public var initialBackoff: RPCDuration {
    willSet { Self.validateInitialBackoff(newValue) }
  }

  /// The maximum amount of time to backoff for. Must be greater than zero.
  public var maxBackoff: RPCDuration {
    willSet { Self.validateMaxBackoff(newValue) }
  }

  /// The multiplier to apply to backoff. Must be greater than zero.
  public var backoffMultiplier: Double {
    willSet { Self.validateBackoffMultiplier(newValue) }
  }

  /// The set of status codes which may be retried. Mustn't be empty.
  public var retryableStatusCodes: [Status.Code] {
    willSet { Self.validateRetryableStatusCodes(newValue) }
  }

  /// Create a new retry policy.
  ///
  /// - Parameters:
  ///   - maxAttempts: The maximum number of attempts allowed for the RPC.
  ///   - initialBackoff: The initial backoff period for the first retry attempt. Must be
  ///       greater than zero.
  ///   - maxBackoff: The maximum period of time to wait between attempts. Must be greater than
  ///       zero.
  ///   - backoffMultiplier: The exponential backoff multiplier. Must be greater than zero.
  ///   - retryableStatusCodes: The set of status codes which may be retried. Must not be empty.
  public init(
    maxAttempts: Int,
    initialBackoff: RPCDuration,
    maxBackoff: RPCDuration,
    backoffMultiplier: Double,
    retryableStatusCodes: [Status.Code]
  ) {
    self.maxAttempts = validateMaxAttempts(maxAttempts)

    Self.validateInitialBackoff(initialBackoff)
    self.initialBackoff = initialBackoff

    Self.validateMaxBackoff(maxBackoff)
    self.maxBackoff = maxBackoff

    Self.validateBackoffMultiplier(backoffMultiplier)
    self.backoffMultiplier = backoffMultiplier

    Self.validateRetryableStatusCodes(retryableStatusCodes)
    self.retryableStatusCodes = retryableStatusCodes
  }

  private static func validateInitialBackoff(_ value: RPCDuration) {
    precondition(value.nanoseconds > 0, "initialBackoff must be greater than zero")
  }

  private static func validateMaxBackoff(_ value: RPCDuration) {
    precondition(value.nanoseconds > 0, "maxBackoff must be greater than zero")
  }

  private static func validateBackoffMultiplier(_ value: Double) {
    precondition(value > 0, "backoffMultiplier must be greater than zero")
  }

  private static func validateRetryableStatusCodes(_ value: [Status.Code]) {
    precondition(!value.isEmpty, "retryableStatusCodes mustn't be empty")
  }
}

/// Policy for hedging an RPC.
///
/// Hedged RPCs may execute more than once on a server so only idempotent methods should
/// be hedged.
///
/// gRPC executes the RPC at most ``maxAttempts`` times, staggering each attempt
/// by ``hedgingDelay``.
///
/// For more information see [gRFC A6 Client
/// Retries](https://github.com/grpc/proposal/blob/master/A6-client-retries.md).
public struct HedgingPolicy: Hashable, Sendable {
  /// The maximum number of RPC attempts, including the original attempt.
  ///
  /// Must be greater than one, values greater than five are treated as five.
  public var maxAttempts: Int {
    didSet { self.maxAttempts = validateMaxAttempts(self.maxAttempts) }
  }

  /// The first RPC will be sent immediately, but each subsequent RPC will be sent at intervals
  /// of `hedgingDelay`. Set this to zero to immediately send all RPCs.
  public var hedgingDelay: RPCDuration {
    willSet { Self.validateHedgingDelay(newValue) }
  }

  /// The set of status codes which indicate other hedged RPCs may still succeed.
  ///
  /// If a non-fatal status code is returned by the server, hedged RPCs will continue.
  /// Otherwise, outstanding requests will be cancelled and the error returned to the
  /// application layer.
  public var nonFatalStatusCodes: [Status.Code]

  public init(
    maxAttempts: Int,
    hedgingDelay: RPCDuration,
    nonFatalStatusCodes: [Status.Code]
  ) {
    self.maxAttempts = validateMaxAttempts(maxAttempts)

    Self.validateHedgingDelay(hedgingDelay)
    self.hedgingDelay = hedgingDelay
    self.nonFatalStatusCodes = nonFatalStatusCodes
  }

  private static func validateHedgingDelay(_ value: RPCDuration) {
    precondition(value.nanoseconds >= 0, "hedgingDelay must be greater than or equal to zero")
  }
}

private func validateMaxAttempts(_ value: Int) -> Int {
  precondition(value > 0, "maxAttempts must be greater than zero")
  return min(value, 5)
}
