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

/// A throttle used to rate-limit retries and hedging attempts.
///
/// gRPC prevents servers from being overloaded by retries and hedging by using a token-based
/// throttling mechanism at the transport level.
///
/// Each client transport maintains a throttle for the server it is connected to and gRPC records
/// successful and failed RPC attempts. Successful attempts increment the number of tokens
/// by ``tokenRatio`` and failed attempts decrement the available tokens by one. In the context
/// of throttling, a failed attempt is one where the server terminates the RPC with a status code
/// which is retryable or non fatal (as defined by ``RetryPolicy/retryableStatusCodes`` and
/// ``HedgingPolicy/nonFatalStatusCodes``) or when the client receives a pushback response from
/// the server.
///
/// See also [gRFC A6: client retries](https://github.com/grpc/proposal/blob/master/A6-client-retries.md).
public struct RetryThrottle: Sendable {
  // Note: only three figures after the decimal point from the original token ratio are used so
  //   all computation is done a scaled number of tokens (tokens * 1000). This allows us to do all
  //   computation in integer space.

  /// The number of tokens available, multiplied by 1000.
  private let scaledTokensAvailable: LockedValueBox<Int>
  /// The number of tokens, multiplied by 1000.
  private let scaledTokenRatio: Int
  /// The maximum number of tokens, multiplied by 1000.
  private let scaledMaximumTokens: Int
  /// The retry threshold, multiplied by 1000. If ``scaledTokensAvailable`` is above this then
  /// retries are permitted.
  private let scaledRetryThreshold: Int

  /// Returns the throttling token ratio.
  ///
  /// The number of tokens held by the throttle is incremented by this value for each successful
  /// response. In the context of throttling, a successful response is one which:
  /// - receives metadata from the server, or
  /// - is terminated with a non-retryable or fatal status code.
  ///
  /// If the response is a pushback response then it is not considered to be successful, even if
  /// either of the preceding conditions are met.
  public var tokenRatio: Double {
    Double(self.scaledTokenRatio) / 1000
  }

  /// The maximum number of tokens the throttle may hold.
  public var maximumTokens: Int {
    self.scaledMaximumTokens / 1000
  }

  /// The number of tokens the throttle currently has.
  ///
  /// If this value is less than or equal to the retry threshold (defined as `maximumTokens / 2`)
  /// then RPCs will not be retried and hedging will be disabled.
  public var tokens: Double {
    self.scaledTokensAvailable.withLockedValue {
      Double($0) / 1000
    }
  }

  /// Returns whether retries and hedging are permitted at this time.
  public var isRetryPermitted: Bool {
    self.scaledTokensAvailable.withLockedValue {
      $0 > self.scaledRetryThreshold
    }
  }

  /// Create a new throttle.
  ///
  /// - Parameters:
  ///   - maximumTokens: The maximum number of tokens available. Must be in the range `1...1000`.
  ///   - tokenRatio: The number of tokens to increment the available tokens by for successful
  ///       responses. See the documentation on this type for a description of what counts as a
  ///       successful response. Note that only three decimal places are used from this value.
  /// - Precondition: `maximumTokens` must be in the range `1...1000`.
  /// - Precondition: `tokenRatio` must be `>= 0.001`.
  public init(maximumTokens: Int, tokenRatio: Double) {
    precondition(
      (1 ... 1000).contains(maximumTokens),
      "maximumTokens must be in the range 1...1000 (is \(maximumTokens))"
    )

    let scaledTokenRatio = Int(tokenRatio * 1000)
    precondition(scaledTokenRatio > 0, "tokenRatio must be >= 0.001 (is \(tokenRatio))")

    let scaledTokens = maximumTokens * 1000
    self.scaledMaximumTokens = scaledTokens
    self.scaledRetryThreshold = scaledTokens / 2
    self.scaledTokenRatio = scaledTokenRatio
    self.scaledTokensAvailable = LockedValueBox(scaledTokens)
  }

  /// Create a new throttle.
  ///
  /// - Parameter policy: The policy to use to configure the throttle.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public init(policy: ServiceConfiguration.RetryThrottlingPolicy) {
    self.init(maximumTokens: policy.maxTokens, tokenRatio: policy.tokenRatio)
  }

  /// Records a success, adding a token to the throttle.
  @usableFromInline
  func recordSuccess() {
    self.scaledTokensAvailable.withLockedValue { value in
      value = min(self.scaledMaximumTokens, value &+ self.scaledTokenRatio)
    }
  }

  /// Records a failure, removing tokens from the throttle.
  /// - Returns: Whether retries will now be throttled.
  @usableFromInline
  @discardableResult
  func recordFailure() -> Bool {
    self.scaledTokensAvailable.withLockedValue { value in
      value = max(0, value &- 1000)
      return value <= self.scaledRetryThreshold
    }
  }
}
