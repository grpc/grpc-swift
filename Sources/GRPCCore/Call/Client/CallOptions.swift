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

/// Options applied to a call.
///
/// If set, these options are used in preference to any options configured on
/// the client or its transport.
///
/// You can create the default set of options, which defers all possible
/// configuration to the transport, by using ``CallOptions/defaults``.
@available(gRPCSwift 2.0, *)
public struct CallOptions: Sendable {
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

  /// Whether RPCs for this method should wait until the connection is ready.
  ///
  /// If `false` the RPC will abort immediately if there is a transient failure connecting to
  /// the server. Otherwise gRPC will attempt to connect until the deadline is exceeded.
  public var waitForReady: Bool?

  /// The maximum allowed payload size in bytes for an individual request message.
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

  /// The compression used for the call.
  ///
  /// Compression in gRPC is asymmetrical: the server may compress response messages using a
  /// different algorithm than the client used to compress request messages. This configuration
  /// controls the compression used by the client for request messages.
  ///
  /// Note that this configuration is advisory: not all transports support compression and may
  /// ignore this configuration. Transports which support compression will use this configuration
  /// in preference to the algorithm configured at a transport level. If the transport hasn't
  /// enabled the use of the algorithm then compression won't be used for the call.
  ///
  /// If `nil` the value configured on the transport will be used instead.
  public var compression: CompressionAlgorithm?

  internal init(
    timeout: Duration?,
    waitForReady: Bool?,
    maxRequestMessageBytes: Int?,
    maxResponseMessageBytes: Int?,
    executionPolicy: RPCExecutionPolicy?,
    compression: CompressionAlgorithm?
  ) {
    self.timeout = timeout
    self.waitForReady = waitForReady
    self.maxRequestMessageBytes = maxRequestMessageBytes
    self.maxResponseMessageBytes = maxResponseMessageBytes
    self.executionPolicy = executionPolicy
    self.compression = compression
  }
}

@available(gRPCSwift 2.0, *)
extension CallOptions {
  /// Default call options.
  ///
  /// The default values (`nil`) defer values to the underlying transport.
  public static var defaults: Self {
    Self(
      timeout: nil,
      waitForReady: nil,
      maxRequestMessageBytes: nil,
      maxResponseMessageBytes: nil,
      executionPolicy: nil,
      compression: nil
    )
  }
}

@available(gRPCSwift 2.0, *)
extension CallOptions {
  package mutating func formUnion(with methodConfig: MethodConfig?) {
    guard let methodConfig = methodConfig else { return }

    self.timeout.setIfNone(to: methodConfig.timeout)
    self.waitForReady.setIfNone(to: methodConfig.waitForReady)
    self.maxRequestMessageBytes.setIfNone(to: methodConfig.maxRequestMessageBytes)
    self.maxResponseMessageBytes.setIfNone(to: methodConfig.maxResponseMessageBytes)
    self.executionPolicy.setIfNone(to: methodConfig.executionPolicy)
  }
}

extension Optional {
  fileprivate mutating func setIfNone(to value: Self) {
    switch self {
    case .some:
      ()
    case .none:
      self = value
    }
  }
}
