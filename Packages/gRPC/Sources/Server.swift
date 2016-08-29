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

/// gRPC Server
public class Server {

  /// Pointer to underlying C representation
  var s: UnsafeMutableRawPointer!

  /// Completion queue used for server operations
  var completionQueue: CompletionQueue

  /// Initializes a Server
  ///
  /// - Parameter address: the address where the server will listen
  public init(address:String) {
    s = cgrpc_server_create(address)
    completionQueue = CompletionQueue(cq:cgrpc_server_get_completion_queue(s))
  }

  deinit {
    cgrpc_server_destroy(s)
  }

  /// Starts the server
  public func start() {
    cgrpc_server_start(s);
  }

  /// Gets the next request sent to the server
  ///
  /// - Returns: a tuple containing the results of waiting and a possible Handler for the request
  public func getNextRequest(timeout: Double) -> (grpc_call_error, grpc_completion_type, Handler?) {
    let handler = Handler(h:cgrpc_handler_create_with_server(s))
    let call_error = handler.requestCall(tag:101)
    if (call_error != GRPC_CALL_OK) {
      return (call_error, GRPC_OP_COMPLETE, nil)
    } else {
      let completion_type = self.completionQueue.waitForCompletion(timeout:timeout)
      if (completion_type == GRPC_OP_COMPLETE) {
        return (GRPC_CALL_OK, GRPC_OP_COMPLETE, handler)
      } else {
        return (GRPC_CALL_OK, completion_type, nil)
      }
    }
  }
}
