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
  private var underlyingChannel: UnsafeMutableRawPointer
  
  /// Completion queue for channel call operations
  private var completionQueue: CompletionQueue
  
  /// Timeout for new calls
  public var timeout: TimeInterval = 600.0
  
  /// Default host to use for new calls
  public var host: String
  
  /// Initializes a gRPC channel
  ///
  /// - Parameter address: the address of the server to be called
  /// - Parameter secure: if true, use TLS
  public init(address: String, secure: Bool = true) {
    host = address
    if secure {
      underlyingChannel = cgrpc_channel_create_secure(address, roots_pem(), nil)
    } else {
      underlyingChannel = cgrpc_channel_create(address)
    }
    completionQueue = CompletionQueue(underlyingCompletionQueue: cgrpc_channel_completion_queue(underlyingChannel))
    completionQueue.name = "Client" // only for debugging
    completionQueue.run() // start a loop that watches the channel's completion queue
  }
  
  /// Initializes a gRPC channel
  ///
  /// - Parameter address: the address of the server to be called
  /// - Parameter certificates: a PEM representation of certificates to use
  /// - Parameter host: an optional hostname override
  public init(address: String, certificates: String, host: String?) {
    self.host = address
    underlyingChannel = cgrpc_channel_create_secure(address, certificates, host)
    completionQueue = CompletionQueue(underlyingCompletionQueue: cgrpc_channel_completion_queue(underlyingChannel))
    completionQueue.name = "Client" // only for debugging
    completionQueue.run() // start a loop that watches the channel's completion queue
  }
  
  deinit {
    cgrpc_channel_destroy(underlyingChannel)
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
