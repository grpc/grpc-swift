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
  import Dispatch
#endif
import Foundation

/// gRPC Server
public class Server {
  /// Pointer to underlying C representation
  private var underlyingServer: UnsafeMutableRawPointer

  /// Completion queue used for server operations
  var completionQueue: CompletionQueue

  /// Active handlers
  private var handlers: NSMutableSet

  /// Mutex for synchronizing access to handlers
  private var handlersMutex: Mutex = Mutex()

  /// Optional callback when server stops serving
  private var onCompletion: (() -> Void)?

  /// Initializes a Server
  ///
  /// - Parameter address: the address where the server will listen
  public init(address: String) {
    underlyingServer = cgrpc_server_create(address)
    completionQueue = CompletionQueue(underlyingCompletionQueue: cgrpc_server_get_completion_queue(underlyingServer))
    completionQueue.name = "Server " + address
    handlers = NSMutableSet()
  }

  /// Initializes a secure Server
  ///
  /// - Parameter address: the address where the server will listen
  /// - Parameter key: the private key for the server's certificates
  /// - Parameter certs: the server's certificates
  public init(address: String, key: String, certs: String) {
    underlyingServer = cgrpc_server_create_secure(address, key, certs)
    completionQueue = CompletionQueue(underlyingCompletionQueue: cgrpc_server_get_completion_queue(underlyingServer))
    completionQueue.name = "Server " + address
    handlers = NSMutableSet()
  }

  deinit {
    cgrpc_server_destroy(underlyingServer)
  }

  /// Run the server
  public func run(dispatchQueue: DispatchQueue = DispatchQueue.global(),
                  handlerFunction: @escaping (Handler) -> Void) {
    cgrpc_server_start(underlyingServer)
    // run the server on a new background thread
    dispatchQueue.async {
      var running = true
      while running {
        do {
          let handler = Handler(underlyingServer: self.underlyingServer)
          try handler.requestCall(tag: 101)
          // block while waiting for an incoming request
          let event = self.completionQueue.wait(timeout: 600)
          if event.type == .complete {
            if event.tag == 101 {
              // run the handler and remove it when it finishes
              if event.success != 0 {
                // hold onto the handler while it runs
                self.handlersMutex.synchronize {
                  self.handlers.add(handler)
                }
                // this will start the completion queue on a new thread
                handler.completionQueue.runToCompletion(callbackQueue: dispatchQueue) {
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
          } else if event.type == .queueTimeout {
            // everything is fine
          } else if event.type == .queueShutdown {
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

  public func onCompletion(completion: @escaping (() -> Void)) {
    onCompletion = completion
  }
}
