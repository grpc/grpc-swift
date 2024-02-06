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

/// Service configuration values.
///
/// See also: https://github.com/grpc/grpc-proto/blob/master/grpc/service_config/service_config.proto
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct ServiceConfiguration: Hashable, Sendable {
  /// Per-method configuration.
  public var methodConfiguration: [MethodConfiguration]

  /// Load balancing policies.
  ///
  /// The client iterates through the list in order and picks the first configuration it supports.
  /// If no policies are supported then the configuration is considered to be invalid.
  public var loadBalancingConfiguration: [LoadBalancingConfiguration]

  /// The policy for throttling retries.
  ///
  /// If a ``RetryThrottlingPolicy`` is provided, gRPC will automatically throttle retry attempts
  /// and hedged RPCs when the client's ratio of failures to successes exceeds a threshold.
  ///
  /// For each server name, the gRPC client will maintain a `token_count` which is initially set
  /// to ``maxTokens``. Every outgoing RPC (regardless of service or method invoked) will change
  /// `token_count` as follows:
  ///
  ///   - Every failed RPC will decrement the `token_count` by 1.
  ///   - Every successful RPC will increment the `token_count` by ``tokenRatio``.
  ///
  /// If `token_count` is less than or equal to `max_tokens / 2`, then RPCs will not be retried
  /// and hedged RPCs will not be sent.
  public var retryThrottlingPolicy: RetryThrottlingPolicy?

  /// Creates a new ``ServiceConfiguration``.
  ///
  /// - Parameters:
  ///   - methodConfiguration: Per-method configuration.
  ///   - loadBalancingConfiguration: Load balancing policies. Clients use the the first supported
  ///       policy when iterating the list in order.
  ///   - retryThrottlingPolicy: Policy for throttling retries.
  public init(
    methodConfiguration: [MethodConfiguration] = [],
    loadBalancingConfiguration: [LoadBalancingConfiguration] = [],
    retryThrottlingPolicy: RetryThrottlingPolicy? = nil
  ) {
    self.methodConfiguration = methodConfiguration
    self.loadBalancingConfiguration = loadBalancingConfiguration
    self.retryThrottlingPolicy = retryThrottlingPolicy
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ServiceConfiguration: Codable {
  private enum CodingKeys: String, CodingKey {
    case methodConfig
    case loadBalancingConfig
    case retryThrottling
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let methodConfiguration = try container.decodeIfPresent(
      [MethodConfiguration].self,
      forKey: .methodConfig
    )
    self.methodConfiguration = methodConfiguration ?? []

    let loadBalancingConfiguration = try container.decodeIfPresent(
      [LoadBalancingConfiguration].self,
      forKey: .loadBalancingConfig
    )
    self.loadBalancingConfiguration = loadBalancingConfiguration ?? []

    self.retryThrottlingPolicy = try container.decodeIfPresent(
      RetryThrottlingPolicy.self,
      forKey: .retryThrottling
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.methodConfiguration, forKey: .methodConfig)
    try container.encode(self.loadBalancingConfiguration, forKey: .loadBalancingConfig)
    try container.encodeIfPresent(self.retryThrottlingPolicy, forKey: .retryThrottling)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ServiceConfiguration {
  /// Configuration used by clients for load-balancing.
  public struct LoadBalancingConfiguration: Hashable, Sendable {
    private enum Value: Hashable, Sendable {
      case pickFirst(PickFirst)
      case roundRobin(RoundRobin)
    }

    private var value: Value?
    private init(_ value: Value) {
      self.value = value
    }

    /// Creates a pick-first load balancing policy.
    ///
    /// - Parameter shuffleAddressList: Whether resolved addresses should be shuffled before
    ///     attempting to connect to them.
    public static func pickFirst(shuffleAddressList: Bool) -> Self {
      Self(.pickFirst(PickFirst(shuffleAddressList: shuffleAddressList)))
    }

    /// Creates a pick-first load balancing policy.
    ///
    /// - Parameter pickFirst: The pick-first load balancing policy.
    public static func pickFirst(_ pickFirst: PickFirst) -> Self {
      Self(.pickFirst(pickFirst))
    }

    /// Creates a round-robin load balancing policy.
    public static var roundRobin: Self {
      Self(.roundRobin(RoundRobin()))
    }

    /// The pick-first policy, if configured.
    public var pickFirst: PickFirst? {
      get {
        switch self.value {
        case .pickFirst(let value):
          return value
        default:
          return nil
        }
      }
      set {
        self.value = newValue.map { .pickFirst($0) }
      }
    }

    /// The round-robin policy, if configured.
    public var roundRobin: RoundRobin? {
      get {
        switch self.value {
        case .roundRobin(let value):
          return value
        default:
          return nil
        }
      }
      set {
        self.value = newValue.map { .roundRobin($0) }
      }
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ServiceConfiguration.LoadBalancingConfiguration {
  /// Configuration for the pick-first load balancing policy.
  public struct PickFirst: Hashable, Sendable, Codable {
    /// Whether the resolved addresses should be shuffled before attempting to connect to them.
    public var shuffleAddressList: Bool

    /// Creates a new pick-first load balancing policy.
    /// - Parameter shuffleAddressList: Whether the resolved addresses should be shuffled before
    ///     attempting to connect to them.
    public init(shuffleAddressList: Bool = false) {
      self.shuffleAddressList = shuffleAddressList
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let shuffle = try container.decodeIfPresent(Bool.self, forKey: .shuffleAddressList) ?? false
      self.shuffleAddressList = shuffle
    }
  }

  /// Configuration for the round-robin load balancing policy.
  public struct RoundRobin: Hashable, Sendable, Codable {
    /// Creates a new round-robin load balancing policy.
    public init() {}
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ServiceConfiguration.LoadBalancingConfiguration: Codable {
  private enum CodingKeys: String, CodingKey {
    case roundRobin = "round_robin"
    case pickFirst = "pick_first"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let value = try container.decodeIfPresent(RoundRobin.self, forKey: .roundRobin) {
      self.value = .roundRobin(value)
    } else if let value = try container.decodeIfPresent(PickFirst.self, forKey: .pickFirst) {
      self.value = .pickFirst(value)
    } else {
      self.value = nil
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self.value {
    case .pickFirst(let value):
      try container.encode(value, forKey: .pickFirst)
    case .roundRobin(let value):
      try container.encode(value, forKey: .roundRobin)
    case .none:
      ()
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ServiceConfiguration {
  public struct RetryThrottlingPolicy: Hashable, Sendable, Codable {
    /// The initial, and maximum number of tokens.
    ///
    /// - Precondition: Must be greater than zero.
    public var maxTokens: Int

    /// The amount of tokens to add on each successful RPC.
    ///
    /// Typically this will be some number between 0 and 1, e.g., 0.1. Up to three decimal places
    /// are supported.
    ///
    /// - Precondition: Must be greater than zero.
    public var tokenRatio: Double

    /// Creates a new retry throttling policy.
    ///
    /// - Parameters:
    ///   - maxTokens: The initial, and maximum number of tokens. Must be greater than zero.
    ///   - tokenRatio: The amount of tokens to add on each successful RPC. Must be greater
    ///       than zero.
    public init(maxTokens: Int, tokenRatio: Double) throws {
      self.maxTokens = maxTokens
      self.tokenRatio = tokenRatio

      try self.validateMaxTokens()
      try self.validateTokenRatio()
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.maxTokens = try container.decode(Int.self, forKey: .maxTokens)
      self.tokenRatio = try container.decode(Double.self, forKey: .tokenRatio)

      try self.validateMaxTokens()
      try self.validateTokenRatio()
    }

    private func validateMaxTokens() throws {
      if self.maxTokens <= 0 {
        throw RuntimeError(code: .invalidArgument, message: "maxTokens must be greater than zero")
      }
    }

    private func validateTokenRatio() throws {
      if self.tokenRatio <= 0 {
        throw RuntimeError(code: .invalidArgument, message: "tokenRatio must be greater than zero")
      }
    }
  }
}
