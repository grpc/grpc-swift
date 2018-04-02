/*
 * Copyright 2016, gRPC Authors All rights reserved.
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

public enum Arg {
  /// Default authority to pass if none specified on call construction.
  case defaultAuthority(String)

  /// Primary user agent. Goes at the start of the user-agent metadata sent
  /// on each request.
  case primaryUserAgent(String)

  /// Secondary user agent. Goes at the end of the user-agent metadata sent
  /// on each request.
  case secondaryUserAgent(String)

  /// After a duration of this time, the client/server pings its peer to see
  /// if the transport is still alive.
  case keepAliveTime(TimeInterval)

  /// After waiting for a duration of this time, if the keepalive ping sender does
  /// not receive the ping ack, it will close the transport.
  case keepAliveTimeout(TimeInterval)

  /// Is it permissible to send keepalive pings without any outstanding streams?
  case keepAlivePermitWithoutCalls(Bool)

  /// The time between the first and second connection attempts.
  case reconnectBackoffInitial(TimeInterval)

  /// The minimum time between subsequent connection attempts.
  case reconnectBackoffMin(TimeInterval)

  /// The maximum time between subsequent connection attempts.
  case reconnectBackoffMax(TimeInterval)

  /// Should we allow receipt of true-binary data on http2 connections?
  /// Defaults to on (true)
  case http2EnableTrueBinary(Bool)

  /// Minimum time between sending successive ping frames without receiving
  /// any data frame.
  case http2MinSentPingInterval(TimeInterval)

  /// Number of pings before needing to send a data frame or header frame.
  /// `0` indicates that an infinite number of pings can be sent without
  /// sending a data frame or header frame.
  case http2MaxPingsWithoutData(UInt)

  /// This *should* be used for testing only.
  /// Override the target name used for SSL host name checking using this
  /// channel argument. If this argument is not specified, the name used
  /// for SSL host name checking will be the target parameter (assuming that the
  /// secure channel is an SSL channel). If this parameter is specified and the
  /// underlying is not an SSL channel, it will just be ignored.
  case sslTargetNameOverride(String)
}

extension Arg {
  func toCArg() -> grpc_arg {
    switch self {
    case let .defaultAuthority(value):
      return arg("grpc.default_authority", value: value)
    case let .primaryUserAgent(value):
      return arg("grpc.primary_user_agent", value: value)
    case let .secondaryUserAgent(value):
      return arg("grpc.secondary_user_agent", value: value)
    case let .keepAliveTime(value):
      return arg("grpc.keepalive_time_ms", value: value * 1_000)
    case let .keepAliveTimeout(value):
      return arg("grpc.keepalive_timeout_ms", value: value * 1_000)
    case let .keepAlivePermitWithoutCalls(value):
      return arg("grpc.keepalive_permit_without_calls", value: value)
    case let .reconnectBackoffMin(value):
      return arg("grpc.min_reconnect_backoff_ms", value: value * 1_000)
    case let .reconnectBackoffMax(value):
      return arg("grpc.max_reconnect_backoff_ms", value: value * 1_000)
    case let .reconnectBackoffInitial(value):
      return arg("grpc.initial_reconnect_backoff_ms", value: value * 1_000)
    case let .http2EnableTrueBinary(value):
      return arg("grpc.http2.true_binary", value: value)
    case let .http2MinSentPingInterval(value):
      return arg("grpc.http2.min_time_between_pings_ms", value: value * 1_000)
    case let .http2MaxPingsWithoutData(value):
      return arg("grpc.http2.max_pings_without_data", value: value)
    case let .sslTargetNameOverride(value):
      return arg("grpc.ssl_target_name_override", value: value)
    }
  }

  private func arg(_ key: String, value: String) -> grpc_arg {
    var arg = grpc_arg()
    arg.key = gpr_strdup(key)
    arg.type = GRPC_ARG_STRING
    arg.value.string = gpr_strdup(value)
    return arg
  }

  private func arg(_ key: String, value: Bool) -> grpc_arg {
    return arg(key, value: Int32(value ? 1 : 0))
  }

  private func arg(_ key: String, value: Double) -> grpc_arg {
    return arg(key, value: Int32(value))
  }

  private func arg(_ key: String, value: UInt) -> grpc_arg {
    return arg(key, value: Int32(value))
  }

  private func arg(_ key: String, value: Int) -> grpc_arg {
    return arg(key, value: Int32(value))
  }

  private func arg(_ key: String, value: Int32) -> grpc_arg {
    var arg = grpc_arg()
    arg.key = gpr_strdup(key)
    arg.type = GRPC_ARG_INTEGER
    arg.value.integer = value
    return arg
  }
}
