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
  private var underlyingServer: UnsafeMutableRawPointer

  /// Completion queue used for server operations
  var completionQueue: CompletionQueue

  /// Active handlers
  private var handlers : NSMutableSet!

  /// Mutex for synchronizing access to handlers
  private var handlersMutex : Mutex = Mutex()

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

  /// Initializes a secure Server
  ///
  /// - Parameter address: the address where the server will listen
  /// - Parameter key: the private key for the server's certificates
  /// - Parameter certs: the server's certificates
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
  public func run(dispatchQueue: DispatchQueue = DispatchQueue.global(),
                  handlerFunction: @escaping (Handler) -> Void) {
    cgrpc_server_start(underlyingServer);
    // run the server on a new background thread
    dispatchQueue.async {
      var running = true
      while(running) {
        do {
          let handler = Handler(underlyingServer:self.underlyingServer)
          try handler.requestCall(tag:101)
          // block while waiting for an incoming request
          let event = self.completionQueue.wait(timeout:600)
          if (event.type == .complete) {
            if event.tag == 101 {
              // run the handler and remove it when it finishes
              if event.success != 0 {
                // hold onto the handler while it runs
                self.handlersMutex.synchronize {
                  self.handlers.add(handler)
                }
                // this will start the completion queue on a new thread
                handler.completionQueue.runToCompletion(callbackQueue:dispatchQueue) {
                  dispatchQueue.async {
                    self.handlersMutex.synchronize {
                      // release the handler when it finishes
                      self.handlers.remove(handler)
                    }
                  }
                }
                // call the handler function on the server thread
                handlerFunction(handler)
              }
            } else if event.tag == 0 {
              running = false // exit the loop
            }
          } else if (event.type == .queueTimeout) {
            // everything is fine
          } else if (event.type == .queueShutdown) {
            running = false
          }
        } catch (let callError) {
          print("server call error: \(callError)")
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
}
