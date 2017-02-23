/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
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
  public init(address: String) {
    self.host = address
    underlyingChannel = cgrpc_channel_create(address)
    completionQueue = CompletionQueue(underlyingCompletionQueue:cgrpc_channel_completion_queue(underlyingChannel))
    completionQueue.name = "Client" // only for debugging
    self.completionQueue.run() // start a loop that watches the channel's completion queue
  }

  /// Initializes a gRPC channel
  ///
  /// - Parameter address: the address of the server to be called
  public init(address: String, certificates: String?, host: String?) {
    self.host = address
    if let certificates = certificates {
      underlyingChannel = cgrpc_channel_create_secure(address, certificates, host)
    } else {
      let bundle = Bundle(for: Channel.self)
      let url = bundle.url(forResource: "roots", withExtension: "pem")!
      let data = try! Data(contentsOf: url)
      let s = String(data: data, encoding: .ascii)
      underlyingChannel = cgrpc_channel_create_secure(address, s, host)
    }
    completionQueue = CompletionQueue(underlyingCompletionQueue:cgrpc_channel_completion_queue(underlyingChannel))
    completionQueue.name = "Client" // only for debugging
    self.completionQueue.run() // start a loop that watches the channel's completion queue
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
  public func makeCall(_ method:String, host:String="") -> Call {
    let host = (host == "") ? self.host : host
    let underlyingCall = cgrpc_channel_create_call(underlyingChannel, method, host, timeout)!
    return Call(underlyingCall:underlyingCall, owned:true, completionQueue:self.completionQueue)
  }
}
