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
/// A service config mostly contains parameters describing how clients connecting to a service
/// should behave (for example, the load balancing policy to use).
///
/// The schema is described by [`grpc/service_config/service_config.proto`](https://github.com/grpc/grpc-proto/blob/0b30c8c05277ab78ec72e77c9cbf66a26684673d/grpc/service_config/service_config.proto)
/// in the `grpc/grpc-proto` GitHub repository although gRPC uses it in its JSON form rather than
/// the Protobuf form.
@available(gRPCSwift 2.0, *)
public struct ServiceConfig: Hashable, Sendable {
  /// Per-method configuration.
  public var methodConfig: [MethodConfig]

  /// Load balancing policies.
  ///
  /// The client iterates through the list in order and picks the first configuration it supports.
  /// If no policies are supported then the configuration is considered to be invalid.
  public var loadBalancingConfig: [LoadBalancingConfig]

  /// The policy for throttling retries.
  ///
  /// If ``RetryThrottling`` is provided, gRPC will automatically throttle retry attempts
  /// and hedged RPCs when the client's ratio of failures to successes exceeds a threshold.
  ///
  /// For each server name, the gRPC client will maintain a `token_count` which is initially set
  /// to ``RetryThrottling-swift.struct/maxTokens``. Every outgoing RPC (regardless of service or
  /// method invoked) will change `token_count` as follows:
  ///
  ///   - Every failed RPC will decrement the `token_count` by 1.
  ///   - Every successful RPC will increment the `token_count` by
  ///   ``RetryThrottling-swift.struct/tokenRatio``.
  ///
  /// If `token_count` is less than or equal to `max_tokens / 2`, then RPCs will not be retried
  /// and hedged RPCs will not be sent.
  public var retryThrottling: RetryThrottling?

  /// Creates a new ``ServiceConfig``.
  ///
  /// - Parameters:
  ///   - methodConfig: Per-method configuration.
  ///   - loadBalancingConfig: Load balancing policies. Clients use the the first supported
  ///       policy when iterating the list in order.
  ///   - retryThrottling: Policy for throttling retries.
  public init(
    methodConfig: [MethodConfig] = [],
    loadBalancingConfig: [LoadBalancingConfig] = [],
    retryThrottling: RetryThrottling? = nil
  ) {
    self.methodConfig = methodConfig
    self.loadBalancingConfig = loadBalancingConfig
    self.retryThrottling = retryThrottling
  }
}

@available(gRPCSwift 2.0, *)
extension ServiceConfig: Codable {
  private enum CodingKeys: String, CodingKey {
    case methodConfig
    case loadBalancingConfig
    case retryThrottling
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let methodConfig = try container.decodeIfPresent(
      [MethodConfig].self,
      forKey: .methodConfig
    )
    self.methodConfig = methodConfig ?? []

    let loadBalancingConfiguration = try container.decodeIfPresent(
      [LoadBalancingConfig].self,
      forKey: .loadBalancingConfig
    )
    self.loadBalancingConfig = loadBalancingConfiguration ?? []

    self.retryThrottling = try container.decodeIfPresent(
      RetryThrottling.self,
      forKey: .retryThrottling
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.methodConfig, forKey: .methodConfig)
    try container.encode(self.loadBalancingConfig, forKey: .loadBalancingConfig)
    try container.encodeIfPresent(self.retryThrottling, forKey: .retryThrottling)
  }
}

@available(gRPCSwift 2.0, *)
extension ServiceConfig {
  /// Configuration used by clients for load-balancing.
  public struct LoadBalancingConfig: Hashable, Sendable {
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

@available(gRPCSwift 2.0, *)
extension ServiceConfig.LoadBalancingConfig {
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

    public init(from decoder: any Decoder) throws {
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

@available(gRPCSwift 2.0, *)
extension ServiceConfig.LoadBalancingConfig: Codable {
  private enum CodingKeys: String, CodingKey {
    case roundRobin = "round_robin"
    case pickFirst = "pick_first"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let value = try container.decodeIfPresent(RoundRobin.self, forKey: .roundRobin) {
      self.value = .roundRobin(value)
    } else if let value = try container.decodeIfPresent(PickFirst.self, forKey: .pickFirst) {
      self.value = .pickFirst(value)
    } else {
      self.value = nil
    }
  }

  public func encode(to encoder: any Encoder) throws {
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

@available(gRPCSwift 2.0, *)
extension ServiceConfig {
  public struct RetryThrottling: Hashable, Sendable, Codable {
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

    public init(from decoder: any Decoder) throws {
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
