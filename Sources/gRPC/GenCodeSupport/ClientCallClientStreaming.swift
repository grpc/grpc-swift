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

import Foundation
import Dispatch
import SwiftProtobuf

public protocol ClientCallClientStreamingBase: class {
  static var method: String { get }
  
  /// Cancel the call.
  func cancel()
  
  // TODO: Move the other, message type-dependent, methods into this protocol. At the moment, this is not possible,
  // as the protocol would then have an associated type requirement (and become pretty much unusable in the process).
}

open class ClientCallClientStreamingImpl<InputType: Message, OutputType: Message>: ClientCallClientStreamingBase {
  open class var method: String { fatalError("needs to be overridden") }
  
  private var call: Call
  
  /// Create a call.
  public init(_ channel: Channel) {
    self.call = channel.makeCall(type(of: self).method)
  }
  
  /// Call this to start a call. Nonblocking.
  public func start(metadata:Metadata, completion: ((CallResult)->())?) throws -> Self {
    try self.call.start(.clientStreaming, metadata:metadata, completion:completion)
    return self
  }
  
  public func send(_ message: InputType, errorHandler:@escaping (Error)->()) throws {
    let messageData = try message.serializedData()
    try call.sendMessage(data:messageData, errorHandler:errorHandler)
  }
  
  public func closeAndReceive(completion:@escaping (OutputType?, ClientError?)->()) throws {
    do {
      try call.receiveMessage() {(responseData) in
        if let responseData = responseData,
          let response = try? OutputType(serializedData:responseData) {
          completion(response, nil)
        } else {
          completion(nil, .invalidMessageReceived)
        }
      }
      try call.close(completion:{})
    } catch (let error) {
      throw error
    }
  }
  
  public func closeAndReceive() throws -> OutputType {
    var returnError : ClientError?
    var returnResponse : OutputType!
    let sem = DispatchSemaphore(value: 0)
    do {
      try closeAndReceive() {response, error in
        returnResponse = response
        returnError = error
        sem.signal()
      }
      _ = sem.wait(timeout: DispatchTime.distantFuture)
    } catch (let error) {
      throw error
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnResponse
  }
  
  public func cancel() {
    call.cancel()
  }
}

/// Simple fake implementation of ClientCallClientStreamingBase that
/// stores sent values for later verification and finally returns a previously-defined result.
open class ClientCallClientStreamingTestStub<InputType: Message, OutputType: Message>: ClientCallClientStreamingBase {
  open class var method: String { fatalError("needs to be overridden") }
  
  var inputs: [InputType] = []
  var output: OutputType?
  
  public func send(_ message: InputType, errorHandler:@escaping (Error)->()) throws {
    inputs.append(message)
  }
  
  public func closeAndReceive(completion:@escaping (OutputType?, ClientError?)->()) throws {
    completion(output!, nil)
  }
  
  public func closeAndReceive() throws -> OutputType {
    return output!
  }
  
  public func cancel() { }
}
