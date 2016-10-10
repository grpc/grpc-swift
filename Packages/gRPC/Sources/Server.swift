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

/// gRPC Server
public class Server {

  /// Pointer to underlying C representation
  var underlyingServer: UnsafeMutableRawPointer!

  /// Completion queue used for server operations
  var completionQueue: CompletionQueue

  /// Active handlers
  var handlers : NSMutableSet!

  /// Optional callback when server stops serving
  private var onCompletion: (() -> Void)!

  /// Initializes a Server
  ///
  /// - Parameter address: the address where the server will listen
  public init(address:String) {
    underlyingServer = cgrpc_server_create(address)
    completionQueue = CompletionQueue(underlyingCompletionQueue:cgrpc_server_get_completion_queue(underlyingServer))
    completionQueue.name = "Server " + address
    handlers = NSMutableSet()
  }

  public init(address:String, key:String, certs:String) {
    underlyingServer = cgrpc_server_create_secure(address, key, certs)
    completionQueue = CompletionQueue(underlyingCompletionQueue:cgrpc_server_get_completion_queue(underlyingServer))
    completionQueue.name = "Server " + address
    handlers = NSMutableSet()
  }

  deinit {
    cgrpc_server_destroy(underlyingServer)
  }

  /// Run the server
  public func run(handlerFunction: @escaping (Handler) -> Void) {
    cgrpc_server_start(underlyingServer);
    DispatchQueue.global().async {
      var running = true
      while(running) {
        let handler = Handler(underlyingHandler:cgrpc_handler_create_with_server(self.underlyingServer))
        let call_error = handler.requestCall(tag:101)
        if (call_error != GRPC_CALL_OK) {
          // not good, let's break
          break
        }
        // blocks
        let event = self.completionQueue.waitForCompletion(timeout:600)
        if (event.type == GRPC_OP_COMPLETE) {
          if cgrpc_event_tag(event) == 101 {
            // run the handler and remove it when it finishes
            if event.success != 0 {
              self.handlers.add(handler)
              handler.completionQueue.run() {
                // on completion
                self.handlers.remove(handler)
              }
              handlerFunction(handler)
            }
          } else if cgrpc_event_tag(event) == 0 {
            running = false // exit the loop
          }
        } else if (event.type == GRPC_QUEUE_TIMEOUT) {
          // everything is fine
        } else if (event.type == GRPC_QUEUE_SHUTDOWN) {
          running = false
        }
      }
      if let onCompletion = self.onCompletion {
        onCompletion()
      }
    }
  }

  public func stop() {
    cgrpc_server_stop(underlyingServer)
  }

  public func onCompletion(completion:@escaping (() -> Void)) -> Void {
    onCompletion = completion
  }

  /// Gets the next request sent to the server
  ///
  /// - Returns: a tuple containing the results of waiting and a possible Handler for the request
  private func getNextRequest(timeout: Double) -> (grpc_call_error, grpc_completion_type, Handler?) {
    let handler = Handler(underlyingHandler:cgrpc_handler_create_with_server(underlyingServer))
    let call_error = handler.requestCall(tag:101)
    if (call_error != GRPC_CALL_OK) {
      return (call_error, GRPC_OP_COMPLETE, nil)
    } else {
      let event = self.completionQueue.waitForCompletion(timeout:timeout)
      if (event.type == GRPC_OP_COMPLETE) {
        handler.completionQueue.run() {
          self.handlers.remove(handler)
        }
        self.handlers.add(handler)
        return (GRPC_CALL_OK, GRPC_OP_COMPLETE, handler)
      } else {
        return (GRPC_CALL_OK, event.type, nil)
      }
    }
  }
}
