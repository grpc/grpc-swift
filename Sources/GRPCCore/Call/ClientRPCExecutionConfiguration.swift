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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct ClientRPCExecutionConfiguration: Hashable, Sendable {
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
  public var timeout: Duration?

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

  /// Create an execution configuration.
  ///
  /// - Parameters:
  ///   - executionPolicy: The execution policy to use for the RPC.
  ///   - timeout: The default timeout for the RPC.
  public init(
    executionPolicy: ExecutionPolicy?,
    timeout: Duration?
  ) {
    self.executionPolicy = executionPolicy
    self.timeout = timeout
  }

  /// Create an execution configuration with a retry policy.
  ///
  /// - Parameters:
  ///   - retryPolicy: The policy for retrying the RPC.
  ///   - timeout: The default timeout for the RPC.
  public init(
    retryPolicy: RetryPolicy,
    timeout: Duration? = nil
  ) {
    self.executionPolicy = .retry(retryPolicy)
    self.timeout = timeout
  }

  /// Create an execution configuration with a hedging policy.
  ///
  /// - Parameters:
  ///   - hedgingPolicy: The policy for hedging the RPC.
  ///   - timeout: The default timeout for the RPC.
  public init(
    hedgingPolicy: HedgingPolicy,
    timeout: Duration? = nil
  ) {
    self.executionPolicy = .hedge(hedgingPolicy)
    self.timeout = timeout
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ClientRPCExecutionConfiguration {
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
/// Execution attempts are limited by ``maximumAttempts`` which includes the original attempt. The
/// maximum number of attempts is limited to five.
///
/// Subsequent attempts are executed after some delay. The first _retry_, or second attempt, will
/// be started after a randomly chosen delay between zero and ``initialBackoff``. More generally,
/// the nth retry will happen after a randomly chosen delay between zero
/// and `min(initialBackoff * backoffMultiplier^(n-1), maximumBackoff)`.
///
/// For more information see [gRFC A6 Client
/// Retries](https://github.com/grpc/proposal/blob/master/A6-client-retries.md).
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct RetryPolicy: Hashable, Sendable {
  /// The maximum number of RPC attempts, including the original attempt.
  ///
  /// Must be greater than one, values greater than five are treated as five.
  public var maximumAttempts: Int {
    didSet { self.maximumAttempts = validateMaxAttempts(self.maximumAttempts) }
  }

  /// The initial backoff duration.
  ///
  /// The initial retry will occur after a random amount of time up to this value.
  ///
  /// - Precondition: Must be greater than zero.
  public var initialBackoff: Duration {
    willSet { Self.validateInitialBackoff(newValue) }
  }

  /// The maximum amount of time to backoff for.
  ///
  /// - Precondition: Must be greater than zero.
  public var maximumBackoff: Duration {
    willSet { Self.validateMaxBackoff(newValue) }
  }

  /// The multiplier to apply to backoff.
  ///
  /// - Precondition: Must be greater than zero.
  public var backoffMultiplier: Double {
    willSet { Self.validateBackoffMultiplier(newValue) }
  }

  /// The set of status codes which may be retried.
  ///
  /// - Precondition: Must not be empty.
  public var retryableStatusCodes: Set<Status.Code> {
    willSet { Self.validateRetryableStatusCodes(newValue) }
  }

  /// Create a new retry policy.
  ///
  /// - Parameters:
  ///   - maximumAttempts: The maximum number of attempts allowed for the RPC.
  ///   - initialBackoff: The initial backoff period for the first retry attempt. Must be
  ///       greater than zero.
  ///   - maximumBackoff: The maximum period of time to wait between attempts. Must be greater than
  ///       zero.
  ///   - backoffMultiplier: The exponential backoff multiplier. Must be greater than zero.
  ///   - retryableStatusCodes: The set of status codes which may be retried. Must not be empty.
  /// - Precondition: `maximumAttempts`, `initialBackoff`, `maximumBackoff` and `backoffMultiplier`
  ///     must be greater than zero.
  /// - Precondition: `retryableStatusCodes` must not be empty.
  public init(
    maximumAttempts: Int,
    initialBackoff: Duration,
    maximumBackoff: Duration,
    backoffMultiplier: Double,
    retryableStatusCodes: Set<Status.Code>
  ) {
    self.maximumAttempts = validateMaxAttempts(maximumAttempts)

    Self.validateInitialBackoff(initialBackoff)
    self.initialBackoff = initialBackoff

    Self.validateMaxBackoff(maximumBackoff)
    self.maximumBackoff = maximumBackoff

    Self.validateBackoffMultiplier(backoffMultiplier)
    self.backoffMultiplier = backoffMultiplier

    Self.validateRetryableStatusCodes(retryableStatusCodes)
    self.retryableStatusCodes = retryableStatusCodes
  }

  private static func validateInitialBackoff(_ value: Duration) {
    precondition(value.isGreaterThanZero, "initialBackoff must be greater than zero")
  }

  private static func validateMaxBackoff(_ value: Duration) {
    precondition(value.isGreaterThanZero, "maximumBackoff must be greater than zero")
  }

  private static func validateBackoffMultiplier(_ value: Double) {
    precondition(value > 0, "backoffMultiplier must be greater than zero")
  }

  private static func validateRetryableStatusCodes(_ value: Set<Status.Code>) {
    precondition(!value.isEmpty, "retryableStatusCodes mustn't be empty")
  }
}

/// Policy for hedging an RPC.
///
/// Hedged RPCs may execute more than once on a server so only idempotent methods should
/// be hedged.
///
/// gRPC executes the RPC at most ``maximumAttempts`` times, staggering each attempt
/// by ``hedgingDelay``.
///
/// For more information see [gRFC A6 Client
/// Retries](https://github.com/grpc/proposal/blob/master/A6-client-retries.md).
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct HedgingPolicy: Hashable, Sendable {
  /// The maximum number of RPC attempts, including the original attempt.
  ///
  /// Values greater than five are treated as five.
  ///
  /// - Precondition: Must be greater than one.
  public var maximumAttempts: Int {
    didSet { self.maximumAttempts = validateMaxAttempts(self.maximumAttempts) }
  }

  /// The first RPC will be sent immediately, but each subsequent RPC will be sent at intervals
  /// of `hedgingDelay`. Set this to zero to immediately send all RPCs.
  public var hedgingDelay: Duration {
    willSet { Self.validateHedgingDelay(newValue) }
  }

  /// The set of status codes which indicate other hedged RPCs may still succeed.
  ///
  /// If a non-fatal status code is returned by the server, hedged RPCs will continue.
  /// Otherwise, outstanding requests will be cancelled and the error returned to the
  /// application layer.
  public var nonFatalStatusCodes: Set<Status.Code>

  /// Create a new hedging policy.
  ///
  /// - Parameters:
  ///   - maximumAttempts: The maximum number of attempts allowed for the RPC.
  ///   - hedgingDelay: The delay between each hedged RPC.
  ///   - nonFatalStatusCodes: The set of status codes which indicated other hedged RPCs may still
  ///       succeed.
  /// - Precondition: `maximumAttempts` must be greater than zero.
  public init(
    maximumAttempts: Int,
    hedgingDelay: Duration,
    nonFatalStatusCodes: Set<Status.Code>
  ) {
    self.maximumAttempts = validateMaxAttempts(maximumAttempts)

    Self.validateHedgingDelay(hedgingDelay)
    self.hedgingDelay = hedgingDelay
    self.nonFatalStatusCodes = nonFatalStatusCodes
  }

  private static func validateHedgingDelay(_ value: Duration) {
    precondition(
      value.isGreaterThanOrEqualToZero,
      "hedgingDelay must be greater than or equal to zero"
    )
  }
}

private func validateMaxAttempts(_ value: Int) -> Int {
  precondition(value > 0, "maximumAttempts must be greater than zero")
  return min(value, 5)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Duration {
  fileprivate var isGreaterThanZero: Bool {
    self.components.seconds > 0 || self.components.attoseconds > 0
  }

  fileprivate var isGreaterThanOrEqualToZero: Bool {
    self.components.seconds >= 0 || self.components.attoseconds >= 0
  }
}
