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
import Foundation

/// A gRPC Channel
public class Channel {
  /// Pointer to underlying C representation
  private let underlyingChannel: UnsafeMutableRawPointer

  /// Completion queue for channel call operations
  private let completionQueue: CompletionQueue

  /// Timeout for new calls
  public var timeout: TimeInterval = 600.0

  /// Default host to use for new calls
  public var host: String
  
  public var connectivityState: ConnectivityState? {
    return ConnectivityState.fromCEnum(cgrpc_channel_check_connectivity_state(underlyingChannel, 0))
  }

  /// Initializes a gRPC channel
  ///
  /// - Parameter address: the address of the server to be called
  /// - Parameter secure: if true, use TLS
  /// - Parameter arguments: list of channel configuration options
  public init(address: String, secure: Bool = true, arguments: [Argument] = []) {
    host = address
    var cargs = arguments.map { $0.toCArg() }

    if secure {
      underlyingChannel = cgrpc_channel_create_secure(address, roots_pem(), &cargs, Int32(arguments.count))
    } else {
      underlyingChannel = cgrpc_channel_create(address, &cargs, Int32(arguments.count))
    }
    completionQueue = CompletionQueue(
      underlyingCompletionQueue: cgrpc_channel_completion_queue(underlyingChannel), name: "Client")
    completionQueue.run() // start a loop that watches the channel's completion queue
  }

  /// Initializes a gRPC channel
  ///
  /// - Parameter address: the address of the server to be called
  /// - Parameter certificates: a PEM representation of certificates to use
  /// - Parameter arguments: list of channel configuration options
  public init(address: String, certificates: String, arguments: [Argument] = []) {
    self.host = address
    var cargs = arguments.map { $0.toCArg() }

    underlyingChannel = cgrpc_channel_create_secure(address, certificates, &cargs, Int32(arguments.count))
    completionQueue = CompletionQueue(
      underlyingCompletionQueue: cgrpc_channel_completion_queue(underlyingChannel), name: "Client")
    completionQueue.run() // start a loop that watches the channel's completion queue
  }

  deinit {
    cgrpc_channel_destroy(underlyingChannel)
    completionQueue.shutdown()
  }

  /// Constructs a Call object to make a gRPC API call
  ///
  /// - Parameter method: the gRPC method name for the call
  /// - Parameter host: the gRPC host name for the call. If unspecified, defaults to the Client host
  /// - Parameter timeout: a timeout value in seconds
  /// - Returns: a Call object that can be used to perform the request
  public func makeCall(_ method: String, host: String = "") -> Call {
    let host = (host == "") ? self.host : host
    let underlyingCall = cgrpc_channel_create_call(underlyingChannel, method, host, timeout)!
    return Call(underlyingCall: underlyingCall, owned: true, completionQueue: completionQueue)
  }
}
