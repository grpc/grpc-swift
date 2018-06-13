/*
 * Copyright 2018, gRPC Authors All rights reserved.
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
#if SWIFT_PACKAGE
  import CgRPC
#endif
import Foundation // for String.Encoding

extension Channel {
  public enum Argument {
    case stringValued(key: String, value: String)
    case integerValued(key: String, value: Int32)
    
    public static func timeIntervalValued(key: String, value: TimeInterval) -> Channel.Argument { return .integerValued(key: key, value: Int32(value * 1_000)) }
    public static func boolValued(key: String, value: Bool) -> Channel.Argument { return .integerValued(key: key, value: Int32(value ? 1 : 0)) }
    
    /// Default authority to pass if none specified on call construction.
    public static func defaultAuthority(_ value: String) -> Channel.Argument { return .stringValued(key: "grpc.default_authority", value: value) }
    
    /// Primary user agent. Goes at the start of the user-agent metadata sent
    /// on each request.
    public static func primaryUserAgent(_ value: String) -> Channel.Argument { return .stringValued(key: "grpc.primary_user_agent", value: value) }
    
    /// Secondary user agent. Goes at the end of the user-agent metadata sent
    /// on each request.
    public static func secondaryUserAgent(_ value: String) -> Channel.Argument { return .stringValued(key: "grpc.secondary_user_agent", value: value) }
    
    /// After a duration of this time, the client/server pings its peer to see
    /// if the transport is still alive.
    public static func keepAliveTime(_ value: TimeInterval) -> Channel.Argument { return .timeIntervalValued(key: "grpc.keepalive_time_ms", value: value) }
    
    /// After waiting for a duration of this time, if the keepalive ping sender does
    /// not receive the ping ack, it will close the transport.
    public static func keepAliveTimeout(_ value: TimeInterval) -> Channel.Argument { return .timeIntervalValued(key: "grpc.keepalive_timeout_ms", value: value) }
    
    /// Is it permissible to send keepalive pings without any outstanding streams?
    public static func keepAlivePermitWithoutCalls(_ value: Bool) -> Channel.Argument { return .boolValued(key: "grpc.keepalive_permit_without_calls", value: value) }
    
    /// The time between the first and second connection attempts.
    public static func reconnectBackoffInitial(_ value: TimeInterval) -> Channel.Argument { return .timeIntervalValued(key: "grpc.initial_reconnect_backoff_ms", value: value) }
    
    /// The minimum time between subsequent connection attempts.
    public static func reconnectBackoffMin(_ value: TimeInterval) -> Channel.Argument { return .timeIntervalValued(key: "grpc.min_reconnect_backoff_ms", value: value) }
    
    /// The maximum time between subsequent connection attempts.
    public static func reconnectBackoffMax(_ value: TimeInterval) -> Channel.Argument { return .timeIntervalValued(key: "grpc.max_reconnect_backoff_ms", value: value) }
    
    /// Should we allow receipt of true-binary data on http2 connections?
    /// Defaults to on (true)
    public static func http2EnableTrueBinary(_ value: Bool) -> Channel.Argument { return .boolValued(key: "grpc.http2.true_binary", value: value) }
    
    /// Minimum time between sending successive ping frames without receiving
    /// any data frame.
    public static func http2MinSentPingInterval(_ value: TimeInterval) -> Channel.Argument { return .timeIntervalValued(key: "grpc.http2.min_time_between_pings_ms", value: value) }
    
    /// Number of pings before needing to send a data frame or header frame.
    /// `0` indicates that an infinite number of pings can be sent without
    /// sending a data frame or header frame.
    public static func http2MaxPingsWithoutData(_ value: UInt32) -> Channel.Argument { return .integerValued(key: "grpc.http2.max_pings_without_data", value: Int32(value)) }
    
    /// This *should* be used for testing only.
    /// Override the target name used for SSL host name checking using this
    /// channel argument. If this argument is not specified, the name used
    /// for SSL host name checking will be the target parameter (assuming that the
    /// secure channel is an SSL channel). If this parameter is specified and the
    /// underlying is not an SSL channel, it will just be ignored.
    public static func sslTargetNameOverride(_ value: String) -> Channel.Argument { return .stringValued(key: "grpc.ssl_target_name_override", value: value) }
    
    /// Enable census for tracing and stats collection.
    public static func enableCensus(_ value: Bool) -> Channel.Argument { return .boolValued(key: "grpc.census", value: value) }
    
    /// Enable load reporting.
    public static func enableLoadReporting(_ value: Bool) -> Channel.Argument { return .boolValued(key: "grpc.loadreporting", value: value) }
    
    /// Request that optional features default to off (regarless of what they usually
    /// default to) - to enable tight control over what gets enabled.
    public static func enableMinimalStack(_ value: Bool) -> Channel.Argument { return .boolValued(key: "grpc.minimal_stack", value: value) }
    
    /// Maximum number of concurrent incoming streams to allow on a http2 connection.
    public static func maxConcurrentStreams(_ value: UInt32) -> Channel.Argument { return .integerValued(key: "grpc.max_concurrent_streams", value: Int32(value)) }
    
    /// Maximum message length that the channel can receive (in byts).
    /// -1 means unlimited.
    public static func maxReceiveMessageLength(_ value: Int32) -> Channel.Argument { return .integerValued(key: "grpc.max_receive_message_length", value: value) }
    
    /// Maximum message length that the channel can send (in bytes).
    /// -1 means unlimited.
    public static func maxSendMessageLength(_ value: Int32) -> Channel.Argument { return .integerValued(key: "grpc.max_send_message_length", value: value) }
    
    /// Maximum time that a channel may have no outstanding rpcs.
    public static func maxConnectionIdle(_ value: TimeInterval) -> Channel.Argument { return .timeIntervalValued(key: "grpc.max_connection_idle_ms", value: value) }
    
    /// Maximum time that a channel may exist.
    public static func maxConnectionAge(_ value: TimeInterval) -> Channel.Argument { return .timeIntervalValued(key: "grpc.max_connection_age_ms", value: value) }
    
    /// Enable/disable support for deadline checking.
    /// Defaults to true, unless `enableMinimalStack` is enabled, in which case it
    /// defaults to false.
    public static func enableDeadlineChecks(_ value: Bool) -> Channel.Argument { return .boolValued(key: "grpc.enable_deadline_checking", value: value) }
  }
}

extension Channel.Argument {
  class Wrapper {
    // Creating a `grpc_arg` allocates memory. This wrapper ensures that the memory is freed after use.
    let wrapped: grpc_arg
    
    init(_ wrapped: grpc_arg) {
      self.wrapped = wrapped
    }
    
    deinit {
      gpr_free(wrapped.key)
      if wrapped.type == GRPC_ARG_STRING {
        gpr_free(wrapped.value.string)
      }
    }
  }
  
  func toCArg() -> Wrapper {
    var arg = grpc_arg()
    switch self {
    case let .stringValued(key, value):
      arg.key = gpr_strdup(key)
      arg.type = GRPC_ARG_STRING
      arg.value.string = gpr_strdup(value)
      
    case let .integerValued(key, value):
      arg.key = gpr_strdup(key)
      arg.type = GRPC_ARG_INTEGER
      arg.value.integer = value
    }
    return Channel.Argument.Wrapper(arg)
  }
}
