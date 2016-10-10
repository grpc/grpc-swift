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

/// A gRPC Client
public class Client {

  /// Pointer to underlying C representation
  var underlyingClient: UnsafeMutableRawPointer!

  /// Completion queue for client call operations
  private var completionQueue: CompletionQueue

  /// Initializes a gRPC client
  ///
  /// - Parameter address: the address of the server to be called
  public init(address: String) {
    underlyingClient = cgrpc_client_create(address)
    completionQueue = CompletionQueue(underlyingCompletionQueue:cgrpc_client_completion_queue(underlyingClient))
    completionQueue.name = "Client" // only for debugging
    self.completionQueue.run() {} // start a loop that watches the client's completion queue
  }

  /// Initializes a gRPC client
  ///
  /// - Parameter address: the address of the server to be called
  public init(address: String, certificates: String?, host: String?) {
    if certificates == nil {
      let bundle = Bundle(for: Client.self)
      let url = bundle.url(forResource: "roots", withExtension: "pem")!
      let data = try! Data(contentsOf: url)
      let s = String(data: data, encoding: .ascii)
      underlyingClient = cgrpc_client_create_secure(address, s, host)
    } else {
      underlyingClient = cgrpc_client_create_secure(address, certificates, host)
    }
    completionQueue = CompletionQueue(underlyingCompletionQueue:cgrpc_client_completion_queue(underlyingClient))
    completionQueue.name = "Client" // only for debugging
    self.completionQueue.run() {} // start a loop that watches the client's completion queue
  }

  deinit {
    cgrpc_client_destroy(underlyingClient)
  }

  /// Constructs a Call object to make a gRPC API call
  ///
  /// - Parameter host: the gRPC host name for the call
  /// - Parameter method: the gRPC method name for the call
  /// - Parameter timeout: a timeout value in seconds
  /// - Returns: a Call object that can be used to perform the request
  public func makeCall(host:String, method:String, timeout:Double) -> Call {
    let call = cgrpc_client_create_call(underlyingClient, method, host, timeout)!
    return Call(call:call, owned:true, completionQueue:self.completionQueue)
  }
}
