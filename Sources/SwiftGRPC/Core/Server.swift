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

  /// Optional callback when server stops serving
  public var onCompletion: (() -> Void)?

  /// Initializes a Server
  ///
  /// - Parameter address: the address where the server will listen
  public init(address: String) {
    underlyingServer = cgrpc_server_create(address)
    completionQueue = CompletionQueue(
      underlyingCompletionQueue: cgrpc_server_get_completion_queue(underlyingServer), name: "Server " + address)
  }

  /// Initializes a secure Server
  ///
  /// - Parameter address: the address where the server will listen
  /// - Parameter key: the private key for the server's certificates
  /// - Parameter certs: the server's certificates
  public init(address: String, key: String, certs: String) {
    underlyingServer = cgrpc_server_create_secure(address, key, certs)
    completionQueue = CompletionQueue(
      underlyingCompletionQueue: cgrpc_server_get_completion_queue(underlyingServer), name: "Server " + address)
  }

  deinit {
    cgrpc_server_destroy(underlyingServer)
    completionQueue.shutdown()
  }

  /// Run the server
  public func run(dispatchQueue: DispatchQueue = DispatchQueue.global(),
                  handlerFunction: @escaping (Handler) -> Void) {
    cgrpc_server_start(underlyingServer)
    // run the server on a new background thread
    let spinloopThreadQueue = DispatchQueue(label: "SwiftGRPC.CompletionQueue.runToCompletion.spinloopThread")
    let handlerDispatchQueue = DispatchQueue(label: "SwiftGRPC.Server.run.dispatchHandler", attributes: .concurrent)
    spinloopThreadQueue.async {
      spinloop: while true {
        do {
          let handler = Handler(underlyingServer: self.underlyingServer)
          try handler.requestCall(tag: Server.handlerCallTag)

          // block while waiting for an incoming request
          let event = self.completionQueue.wait(timeout: 600)

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
                  handlerDispatchQueue.async {
                    // release the handler when it finishes
                    strongHandlerReference = nil
                  }
                }
                handlerDispatchQueue.async {
                  // dispatch the handler function on a separate thread
                  handlerFunction(handler)
                }
              }
            } else if event.tag == Server.stopTag || event.tag == Server.destroyTag {
              break spinloop
            }
          } else if event.type == .queueTimeout {
            // everything is fine
            continue
          } else if event.type == .queueShutdown {
            break spinloop
          }
        } catch {
          print("server call error: \(error)")
          break spinloop
        }
      }
      self.onCompletion?()
    }
  }

  public func stop() {
    cgrpc_server_stop(underlyingServer)
  }
}
