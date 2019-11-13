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
  static let handlerCallTag = 101
  
  // These are sent by the CgRPC shim.
  static let stopTag = 0
  static let destroyTag = 1000
  
  /// Pointer to underlying C representation
  private let underlyingServer: UnsafeMutableRawPointer

  /// Completion queue used for server operations
  let completionQueue: CompletionQueue

  /// Delay for which the spin loop should wait before starting over.
  let loopTimeout: TimeInterval

  /// Optional callback when server stops serving
  public var onCompletion: (() -> Void)?

  /// Initializes a Server
  ///
  /// - Parameter address: the address where the server will listen
  /// - Parameter loopTimeout: delay for which the spin loop should wait before starting over.
  public init(address: String, loopTimeout: TimeInterval = 600) {
    underlyingServer = cgrpc_server_create(address)
    completionQueue = CompletionQueue(
      underlyingCompletionQueue: cgrpc_server_get_completion_queue(underlyingServer), name: "Server " + address)
    self.loopTimeout = loopTimeout
  }

  /// Initializes a secure Server
  ///
  /// - Parameter address: the address where the server will listen
  /// - Parameter key: the private key for the server's certificates
  /// - Parameter certs: the server's certificates
  /// - Parameter rootCerts: used to validate client certificates; will enable enforcing valid client certificates when provided
  /// - Parameter loopTimeout: delay for which the spin loop should wait before starting over.
  public init(address: String, key: String, certs: String, rootCerts: String? = nil, loopTimeout: TimeInterval = 600) {
    underlyingServer = cgrpc_server_create_secure(address, key, certs, rootCerts, rootCerts == nil ? 0 : 1)
    completionQueue = CompletionQueue(
      underlyingCompletionQueue: cgrpc_server_get_completion_queue(underlyingServer), name: "Server " + address)
    self.loopTimeout = loopTimeout
  }

  deinit {
    cgrpc_server_destroy(underlyingServer)
    completionQueue.shutdown()
  }

  /// Run the server.
  ///
  /// - Parameter handlerFunction: will be called to handle an incoming request. Dispatched on a new thread, so can be blocking.
  public func run(handlerFunction: @escaping (Handler) -> Void) {
    cgrpc_server_start(underlyingServer)
    // run the server on a new background thread
    let spinloopThreadQueue = DispatchQueue(label: "SwiftGRPC.CompletionQueue.runToCompletion.spinloopThread")
    spinloopThreadQueue.async {
      do {
        // Allocate a handler _outside_ the spin loop, as we must use _this particular_ handler to serve the next call
        // once we have called `handler.requestCall`. In particular, we need to keep the current handler for the next
        // spin loop interation when we hit the `.queueTimeout` case. The handler should only be replaced once it is
        // "used up" for serving an incoming call.
        var handler = Handler(underlyingServer: self.underlyingServer)
        // Tell gRPC to store the next call's information in this handler object.
        try handler.requestCall(tag: Server.handlerCallTag)
        spinloop: while true {
          // block while waiting for an incoming request
          let event = self.completionQueue.wait(timeout: self.loopTimeout)

          if event.type == .complete {
            if event.tag == Server.handlerCallTag {
              // run the handler and remove it when it finishes
              if event.success != 0 {
                // hold onto the handler while it runs
                var strongHandlerReference: Handler?
                strongHandlerReference = handler
                // To prevent the "Variable 'strongHandlerReference' was written to, but never read" warning.
                _ = strongHandlerReference
                // this will start the completion queue on a new thread
                handler.completionQueue.runToCompletion {
                  // release the handler when it finishes
                  strongHandlerReference = nil
                }
                
                // Dispatch the handler function on a separate thread.
                let handlerDispatchThreadQueue = DispatchQueue(label: "SwiftGRPC.Server.run.dispatchHandlerThread")
                // Needs to be copied, because we will change the value of `handler` right after this.
                let handlerCopy = handler
                handlerDispatchThreadQueue.async {
                  handlerFunction(handlerCopy)
                }
              }

              // This handler has now been "used up" for the current call; replace it with a fresh one for the next
              // loop iteration.
              handler = Handler(underlyingServer: self.underlyingServer)
              try handler.requestCall(tag: Server.handlerCallTag)
            } else if event.tag == Server.stopTag || event.tag == Server.destroyTag {
              break spinloop
            }
          } else if event.type == .queueTimeout {
            // Everything is fine, just start over *while continuing to use the existing handler*.
            continue
          } else if event.type == .queueShutdown {
            break spinloop
          }
        }
      } catch {
        print("server call error: \(error)")
      }
      self.onCompletion?()
    }
  }

  public func stop() {
    cgrpc_server_stop(underlyingServer)
  }
}
