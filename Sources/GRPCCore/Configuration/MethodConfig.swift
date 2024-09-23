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
///
/// See also: https://github.com/grpc/grpc-proto/blob/master/grpc/service_config/service_config.proto
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct MethodConfig: Hashable, Sendable {
  public struct Name: Sendable, Hashable {
    /// The name of the service, including the namespace.
    ///
    /// If the service is empty then `method` must also be empty and the configuration specifies
    /// defaults for all methods.
    ///
    /// - Precondition: If `service` is empty then `method` must also be empty.
    public var service: String {
      didSet { try! self.validate() }
    }

    /// The name of the method.
    ///
    /// If the method is empty then the configuration will be the default for all methods in the
    /// specified service.
    public var method: String

    /// Create a new name.
    ///
    /// If the service is empty then `method` must also be empty and the configuration specifies
    /// defaults for all methods. If only `method` is empty then the configuration applies to
    /// all methods in the `service`.
    ///
    /// - Parameters:
    ///   - service: The name of the service, including the namespace.
    ///   - method: The name of the method.
    public init(service: String, method: String = "") {
      self.service = service
      self.method = method
      try! self.validate()
    }

    private func validate() throws {
      if self.service.isEmpty && !self.method.isEmpty {
        throw RuntimeError(
          code: .invalidArgument,
          message: "'method' must be empty if 'service' is empty."
        )
      }
    }
  }

  /// The names of methods which this configuration applies to.
  public var names: [Name]

  /// Whether RPCs for this method should wait until the connection is ready.
  ///
  /// If `false` the RPC will abort immediately if there is a transient failure connecting to
  /// the server. Otherwise gRPC will attempt to connect until the deadline is exceeded.
  public var waitForReady: Bool?

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

  /// The maximum allowed payload size in bytes for an individual message.
  ///
  /// If a client attempts to send an object larger than this value, it will not be sent and the
  /// client will see an error. Note that 0 is a valid value, meaning that the request message
  /// must be empty.
  ///
  /// Note that if compression is used the uncompressed message size is validated.
  public var maxRequestMessageBytes: Int?

  /// The maximum allowed payload size in bytes for an individual response message.
  ///
  /// If a server attempts to send an object larger than this value, it will not
  /// be sent, and an error will be sent to the client instead. Note that 0 is a valid value,
  /// meaning that the response message must be empty.
  ///
  /// Note that if compression is used the uncompressed message size is validated.
  public var maxResponseMessageBytes: Int?

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
  public var executionPolicy: RPCExecutionPolicy?

  /// Create an execution configuration.
  ///
  /// - Parameters:
  ///   - names: The names of methods this configuration applies to.
  ///   - waitForReady: Whether RPCs sent to this method should wait until the connection is ready.
  ///   - timeout: The default timeout for the RPC.
  ///   - maxRequestMessageBytes: The maximum allowed size of a request message in bytes.
  ///   - maxResponseMessageBytes: The maximum allowed size of a response message in bytes.
  ///   - executionPolicy: The execution policy to use for the RPC.
  public init(
    names: [Name],
    waitForReady: Bool? = nil,
    timeout: Duration? = nil,
    maxRequestMessageBytes: Int? = nil,
    maxResponseMessageBytes: Int? = nil,
    executionPolicy: RPCExecutionPolicy? = nil
  ) {
    self.names = names
    self.waitForReady = waitForReady
    self.timeout = timeout
    self.maxRequestMessageBytes = maxRequestMessageBytes
    self.maxResponseMessageBytes = maxResponseMessageBytes
    self.executionPolicy = executionPolicy
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct RPCExecutionPolicy: Hashable, Sendable {
  @usableFromInline
  enum Wrapped: Hashable, Sendable {
    /// Policy for retrying an RPC.
    ///
    /// See ``RetryPolicy`` for more details.
    case retry(RetryPolicy)

    /// Policy for hedging an RPC.
    ///
    /// See ``HedgingPolicy`` for more details.
    case hedge(HedgingPolicy)
  }

  @usableFromInline
  let wrapped: Wrapped

  private init(_ wrapped: Wrapped) {
    self.wrapped = wrapped
  }

  /// Returns the retry policy, if it was set.
  public var retry: RetryPolicy? {
    switch self.wrapped {
    case .retry(let policy):
      return policy
    case .hedge:
      return nil
    }
  }

  /// Returns the hedging policy, if it was set.
  public var hedge: HedgingPolicy? {
    switch self.wrapped {
    case .hedge(let policy):
      return policy
    case .retry:
      return nil
    }
  }

  /// Create a new retry policy.``
  public static func retry(_ policy: RetryPolicy) -> Self {
    Self(.retry(policy))
  }

  /// Create a new hedging policy.``
  public static func hedge(_ policy: HedgingPolicy) -> Self {
    Self(.hedge(policy))
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct RetryPolicy: Hashable, Sendable {
  /// The maximum number of RPC attempts, including the original attempt.
  ///
  /// Must be greater than one, values greater than five are treated as five.
  public var maxAttempts: Int {
    didSet { self.maxAttempts = try! validateMaxAttempts(self.maxAttempts) }
  }

  /// The initial backoff duration.
  ///
  /// The initial retry will occur after a random amount of time up to this value.
  ///
  /// - Precondition: Must be greater than zero.
  public var initialBackoff: Duration {
    willSet { try! Self.validateInitialBackoff(newValue) }
  }

  /// The maximum amount of time to backoff for.
  ///
  /// - Precondition: Must be greater than zero.
  public var maxBackoff: Duration {
    willSet { try! Self.validateMaxBackoff(newValue) }
  }

  /// The multiplier to apply to backoff.
  ///
  /// - Precondition: Must be greater than zero.
  public var backoffMultiplier: Double {
    willSet { try! Self.validateBackoffMultiplier(newValue) }
  }

  /// The set of status codes which may be retried.
  ///
  /// - Precondition: Must not be empty.
  public var retryableStatusCodes: Set<Status.Code> {
    willSet { try! Self.validateRetryableStatusCodes(newValue) }
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
  /// - Precondition: `maxAttempts`, `initialBackoff`, `maxBackoff` and `backoffMultiplier`
  ///     must be greater than zero.
  /// - Precondition: `retryableStatusCodes` must not be empty.
  public init(
    maxAttempts: Int,
    initialBackoff: Duration,
    maxBackoff: Duration,
    backoffMultiplier: Double,
    retryableStatusCodes: Set<Status.Code>
  ) {
    self.maxAttempts = try! validateMaxAttempts(maxAttempts)

    try! Self.validateInitialBackoff(initialBackoff)
    self.initialBackoff = initialBackoff

    try! Self.validateMaxBackoff(maxBackoff)
    self.maxBackoff = maxBackoff

    try! Self.validateBackoffMultiplier(backoffMultiplier)
    self.backoffMultiplier = backoffMultiplier

    try! Self.validateRetryableStatusCodes(retryableStatusCodes)
    self.retryableStatusCodes = retryableStatusCodes
  }

  private static func validateInitialBackoff(_ value: Duration) throws {
    if value <= .zero {
      throw RuntimeError(
        code: .invalidArgument,
        message: "initialBackoff must be greater than zero"
      )
    }
  }

  private static func validateMaxBackoff(_ value: Duration) throws {
    if value <= .zero {
      throw RuntimeError(
        code: .invalidArgument,
        message: "maxBackoff must be greater than zero"
      )
    }
  }

  private static func validateBackoffMultiplier(_ value: Double) throws {
    if value <= 0 {
      throw RuntimeError(
        code: .invalidArgument,
        message: "backoffMultiplier must be greater than zero"
      )
    }
  }

  private static func validateRetryableStatusCodes(_ value: Set<Status.Code>) throws {
    if value.isEmpty {
      throw RuntimeError(code: .invalidArgument, message: "retryableStatusCodes mustn't be empty")
    }
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
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct HedgingPolicy: Hashable, Sendable {
  /// The maximum number of RPC attempts, including the original attempt.
  ///
  /// Values greater than five are treated as five.
  ///
  /// - Precondition: Must be greater than one.
  public var maxAttempts: Int {
    didSet { self.maxAttempts = try! validateMaxAttempts(self.maxAttempts) }
  }

  /// The first RPC will be sent immediately, but each subsequent RPC will be sent at intervals
  /// of `hedgingDelay`. Set this to zero to immediately send all RPCs.
  public var hedgingDelay: Duration {
    willSet { try! Self.validateHedgingDelay(newValue) }
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
  ///   - maxAttempts: The maximum number of attempts allowed for the RPC.
  ///   - hedgingDelay: The delay between each hedged RPC.
  ///   - nonFatalStatusCodes: The set of status codes which indicate other hedged RPCs may still
  ///       succeed.
  /// - Precondition: `maxAttempts` must be greater than zero.
  public init(
    maxAttempts: Int,
    hedgingDelay: Duration,
    nonFatalStatusCodes: Set<Status.Code>
  ) {
    self.maxAttempts = try! validateMaxAttempts(maxAttempts)

    try! Self.validateHedgingDelay(hedgingDelay)
    self.hedgingDelay = hedgingDelay
    self.nonFatalStatusCodes = nonFatalStatusCodes
  }

  private static func validateHedgingDelay(_ value: Duration) throws {
    if value < .zero {
      throw RuntimeError(
        code: .invalidArgument,
        message: "hedgingDelay must be greater than or equal to zero"
      )
    }
  }
}

private func validateMaxAttempts(_ value: Int) throws -> Int {
  guard value > 1 else {
    throw RuntimeError(
      code: .invalidArgument,
      message: "max_attempts must be greater than one (was \(value))"
    )
  }

  return min(value, 5)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension Duration {
  fileprivate init(googleProtobufDuration duration: String) throws {
    guard duration.utf8.last == UInt8(ascii: "s"),
      let fractionalSeconds = Double(duration.dropLast())
    else {
      throw RuntimeError(code: .invalidArgument, message: "Invalid google.protobuf.duration")
    }

    let seconds = fractionalSeconds.rounded(.down)
    let attoseconds = (fractionalSeconds - seconds) / 1e18

    self.init(secondsComponent: Int64(seconds), attosecondsComponent: Int64(attoseconds))
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension MethodConfig: Codable {
  private enum CodingKeys: String, CodingKey {
    case name
    case waitForReady
    case timeout
    case maxRequestMessageBytes
    case maxResponseMessageBytes
    case retryPolicy
    case hedgingPolicy
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.names = try container.decode([Name].self, forKey: .name)

    let waitForReady = try container.decodeIfPresent(Bool.self, forKey: .waitForReady)
    self.waitForReady = waitForReady

    let timeout = try container.decodeIfPresent(GoogleProtobufDuration.self, forKey: .timeout)
    self.timeout = timeout?.duration

    let maxRequestSize = try container.decodeIfPresent(Int.self, forKey: .maxRequestMessageBytes)
    self.maxRequestMessageBytes = maxRequestSize

    let maxResponseSize = try container.decodeIfPresent(Int.self, forKey: .maxResponseMessageBytes)
    self.maxResponseMessageBytes = maxResponseSize

    if let policy = try container.decodeIfPresent(HedgingPolicy.self, forKey: .hedgingPolicy) {
      self.executionPolicy = .hedge(policy)
    } else if let policy = try container.decodeIfPresent(RetryPolicy.self, forKey: .retryPolicy) {
      self.executionPolicy = .retry(policy)
    } else {
      self.executionPolicy = nil
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.names, forKey: .name)
    try container.encodeIfPresent(self.waitForReady, forKey: .waitForReady)
    try container.encodeIfPresent(
      self.timeout.map { GoogleProtobufDuration(duration: $0) },
      forKey: .timeout
    )
    try container.encodeIfPresent(self.maxRequestMessageBytes, forKey: .maxRequestMessageBytes)
    try container.encodeIfPresent(self.maxResponseMessageBytes, forKey: .maxResponseMessageBytes)

    switch self.executionPolicy?.wrapped {
    case .retry(let policy):
      try container.encode(policy, forKey: .retryPolicy)
    case .hedge(let policy):
      try container.encode(policy, forKey: .hedgingPolicy)
    case .none:
      ()
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension MethodConfig.Name: Codable {
  private enum CodingKeys: String, CodingKey {
    case service
    case method
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let service = try container.decodeIfPresent(String.self, forKey: .service)
    self.service = service ?? ""

    let method = try container.decodeIfPresent(String.self, forKey: .method)
    self.method = method ?? ""

    try self.validate()
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.method, forKey: .method)
    try container.encode(self.service, forKey: .service)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension RetryPolicy: Codable {
  private enum CodingKeys: String, CodingKey {
    case maxAttempts
    case initialBackoff
    case maxBackoff
    case backoffMultiplier
    case retryableStatusCodes
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let maxAttempts = try container.decode(Int.self, forKey: .maxAttempts)
    self.maxAttempts = try validateMaxAttempts(maxAttempts)

    let initialBackoff = try container.decode(String.self, forKey: .initialBackoff)
    self.initialBackoff = try Duration(googleProtobufDuration: initialBackoff)
    try Self.validateInitialBackoff(self.initialBackoff)

    let maxBackoff = try container.decode(String.self, forKey: .maxBackoff)
    self.maxBackoff = try Duration(googleProtobufDuration: maxBackoff)
    try Self.validateMaxBackoff(self.maxBackoff)

    self.backoffMultiplier = try container.decode(Double.self, forKey: .backoffMultiplier)
    try Self.validateBackoffMultiplier(self.backoffMultiplier)

    let codes = try container.decode([GoogleRPCCode].self, forKey: .retryableStatusCodes)
    self.retryableStatusCodes = Set(codes.map { $0.code })
    try Self.validateRetryableStatusCodes(self.retryableStatusCodes)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.maxAttempts, forKey: .maxAttempts)
    try container.encode(
      GoogleProtobufDuration(duration: self.initialBackoff),
      forKey: .initialBackoff
    )
    try container.encode(GoogleProtobufDuration(duration: self.maxBackoff), forKey: .maxBackoff)
    try container.encode(self.backoffMultiplier, forKey: .backoffMultiplier)
    try container.encode(
      self.retryableStatusCodes.map { $0.googleRPCCode },
      forKey: .retryableStatusCodes
    )
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension HedgingPolicy: Codable {
  private enum CodingKeys: String, CodingKey {
    case maxAttempts
    case hedgingDelay
    case nonFatalStatusCodes
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let maxAttempts = try container.decode(Int.self, forKey: .maxAttempts)
    self.maxAttempts = try validateMaxAttempts(maxAttempts)

    let delay = try container.decode(String.self, forKey: .hedgingDelay)
    self.hedgingDelay = try Duration(googleProtobufDuration: delay)

    let statusCodes = try container.decode([GoogleRPCCode].self, forKey: .nonFatalStatusCodes)
    self.nonFatalStatusCodes = Set(statusCodes.map { $0.code })
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.maxAttempts, forKey: .maxAttempts)
    try container.encode(GoogleProtobufDuration(duration: self.hedgingDelay), forKey: .hedgingDelay)
    try container.encode(
      self.nonFatalStatusCodes.map { $0.googleRPCCode },
      forKey: .nonFatalStatusCodes
    )
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct GoogleProtobufDuration: Codable {
  var duration: Duration

  init(duration: Duration) {
    self.duration = duration
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let duration = try container.decode(String.self)

    guard duration.utf8.last == UInt8(ascii: "s"),
      let fractionalSeconds = Double(duration.dropLast())
    else {
      throw RuntimeError(code: .invalidArgument, message: "Invalid google.protobuf.duration")
    }

    let seconds = fractionalSeconds.rounded(.down)
    let attoseconds = (fractionalSeconds - seconds) * 1e18

    self.duration = Duration(
      secondsComponent: Int64(seconds),
      attosecondsComponent: Int64(attoseconds)
    )
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()

    var seconds = Double(self.duration.components.seconds)
    seconds += Double(self.duration.components.attoseconds) / 1e18

    let durationString = "\(seconds)s"
    try container.encode(durationString)
  }
}

struct GoogleRPCCode: Codable {
  var code: Status.Code

  init(code: Status.Code) {
    self.code = code
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let code: Status.Code?

    if let caseName = try? container.decode(String.self) {
      code = Status.Code(googleRPCCode: caseName)
    } else if let rawValue = try? container.decode(Int.self) {
      code = Status.Code(rawValue: rawValue)
    } else {
      code = nil
    }

    if let code = code {
      self.code = code
    } else {
      throw RuntimeError(code: .invalidArgument, message: "Invalid google.rpc.code")
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.code.googleRPCCode)
  }
}

extension Status.Code {
  fileprivate init?(googleRPCCode code: String) {
    switch code {
    case "OK":
      self = .ok
    case "CANCELLED":
      self = .cancelled
    case "UNKNOWN":
      self = .unknown
    case "INVALID_ARGUMENT":
      self = .invalidArgument
    case "DEADLINE_EXCEEDED":
      self = .deadlineExceeded
    case "NOT_FOUND":
      self = .notFound
    case "ALREADY_EXISTS":
      self = .alreadyExists
    case "PERMISSION_DENIED":
      self = .permissionDenied
    case "RESOURCE_EXHAUSTED":
      self = .resourceExhausted
    case "FAILED_PRECONDITION":
      self = .failedPrecondition
    case "ABORTED":
      self = .aborted
    case "OUT_OF_RANGE":
      self = .outOfRange
    case "UNIMPLEMENTED":
      self = .unimplemented
    case "INTERNAL":
      self = .internalError
    case "UNAVAILABLE":
      self = .unavailable
    case "DATA_LOSS":
      self = .dataLoss
    case "UNAUTHENTICATED":
      self = .unauthenticated
    default:
      return nil
    }
  }

  fileprivate var googleRPCCode: String {
    switch self.wrapped {
    case .ok:
      return "OK"
    case .cancelled:
      return "CANCELLED"
    case .unknown:
      return "UNKNOWN"
    case .invalidArgument:
      return "INVALID_ARGUMENT"
    case .deadlineExceeded:
      return "DEADLINE_EXCEEDED"
    case .notFound:
      return "NOT_FOUND"
    case .alreadyExists:
      return "ALREADY_EXISTS"
    case .permissionDenied:
      return "PERMISSION_DENIED"
    case .resourceExhausted:
      return "RESOURCE_EXHAUSTED"
    case .failedPrecondition:
      return "FAILED_PRECONDITION"
    case .aborted:
      return "ABORTED"
    case .outOfRange:
      return "OUT_OF_RANGE"
    case .unimplemented:
      return "UNIMPLEMENTED"
    case .internalError:
      return "INTERNAL"
    case .unavailable:
      return "UNAVAILABLE"
    case .dataLoss:
      return "DATA_LOSS"
    case .unauthenticated:
      return "UNAUTHENTICATED"
    }
  }
}
