/*
 * Copyright 2018, gRPC Authors All rights reserved.
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

import Dispatch
import Foundation
import SwiftProtobuf

open class ServiceServer {
  public let address: String
  public let server: Server

  /// Create a server that accepts insecure connections.
  public init(address: String) {
    gRPC.initialize()
    self.address = address
    server = Server(address: address)
  }

  /// Create a server that accepts secure connections.
  public init(address: String, certificateString: String, keyString: String) {
    gRPC.initialize()
    self.address = address
    server = Server(address: address, key: keyString, certs: certificateString)
  }

  /// Create a server that accepts secure connections.
  public init?(address: String, certificateURL: URL, keyURL: URL) {
    guard let certificate = try? String(contentsOf: certificateURL, encoding: .utf8),
      let key = try? String(contentsOf: keyURL, encoding: .utf8)
      else { return nil }
    gRPC.initialize()
    self.address = address
    server = Server(address: address, key: key, certs: certificate)
  }

  /// Handle the given method. Needs to be overridden by actual implementations.
  /// Returns whether the method was actually handled.
  open func handleMethod(_ method: String, handler: Handler, queue: DispatchQueue) throws -> Bool { fatalError("needs to be overridden") }

  /// Start the server.
  public func start(queue: DispatchQueue = DispatchQueue.global()) {
    server.run { [weak self] handler in
      guard let strongSelf = self else {
        print("ERROR: ServiceServer has been asked to handle a request even though it has already been deallocated")
        return
      }

      let unwrappedHost = handler.host ?? "(nil)"
      let unwrappedMethod = handler.method ?? "(nil)"
      let unwrappedCaller = handler.caller ?? "(nil)"
      print("Server received request to " + unwrappedHost
        + " calling " + unwrappedMethod
        + " from " + unwrappedCaller
        + " with " + handler.requestMetadata.description)

      do {
        if try !strongSelf.handleMethod(unwrappedMethod, handler: handler, queue: queue) {
          // handle unknown requests
          try handler.sendResponse(statusCode: .unimplemented,
                                   statusMessage: "unknown method " + unwrappedMethod,
                                   trailingMetadata: Metadata())
        }
      } catch (let error) {
        print("Server error: \(error)")
      }
    }
  }
}
