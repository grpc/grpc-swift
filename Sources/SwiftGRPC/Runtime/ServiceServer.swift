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

  public var shouldLogRequests = true

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

  public enum HandleMethodError: Error {
    case unknownMethod
  }
  
  /// Handle the given method. Needs to be overridden by actual implementations.
  /// Returns whether the method was actually handled.
  open func handleMethod(_ method: String, handler: Handler) throws -> ServerStatus? { fatalError("needs to be overridden") }

  /// Start the server.
  public func start() {
    server.run { [weak self] handler in
      guard let strongSelf = self else {
        print("ERROR: ServiceServer has been asked to handle a request even though it has already been deallocated")
        return
      }

      let unwrappedMethod = handler.method ?? "(nil)"
      if strongSelf.shouldLogRequests == true {
        let unwrappedHost = handler.host ?? "(nil)"
        let unwrappedCaller = handler.caller ?? "(nil)"
        print("Server received request to " + unwrappedHost
          + " calling " + unwrappedMethod
          + " from " + unwrappedCaller
          + " with metadata " + handler.requestMetadata.dictionaryRepresentation.description)
      }
      
      do {
        do {
          if let responseStatus = try strongSelf.handleMethod(unwrappedMethod, handler: handler),
            !handler.completionQueue.hasBeenShutdown {
            // The handler wants us to send the status for them; do that.
            // But first, ensure that all outgoing messages have been enqueued, to avoid ending the stream prematurely:
            handler.call.messageQueueEmpty.wait()
            try handler.sendStatus(responseStatus)
          }
        } catch _ as HandleMethodError {
          if !handler.completionQueue.hasBeenShutdown {
            // The method is not implemented by the service - send a status saying so.
            try handler.call.perform(OperationGroup(
              call: handler.call,
              operations: [
                .sendInitialMetadata(Metadata()),
                .receiveCloseOnServer,
                .sendStatusFromServer(.unimplemented, "unknown method " + unwrappedMethod, Metadata())
            ]) { _ in
              handler.shutdown()
            })
          }
        }
      } catch {
        // The individual sessions' `run` methods (which are called by `self.handleMethod`) only throw errors if
        // they encountered an error that has not also been "seen" by the actual request handler implementation.
        // Therefore, this error is "really unexpected" and  should be logged here - there's nowhere else to log it otherwise.
        print("ServiceServer unexpected error handling method '\(unwrappedMethod)': \(error)")
        do {
          if !handler.completionQueue.hasBeenShutdown {
            try handler.sendStatus((error as? ServerStatus) ?? .processingError)
          }
        } catch {
          print("ServiceServer unexpected error handling method '\(unwrappedMethod)'; sending status failed as well: \(error)")
          handler.shutdown()
        }
      }
    }
  }
}
