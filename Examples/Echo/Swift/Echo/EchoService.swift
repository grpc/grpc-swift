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
import Foundation
import gRPC

// all code that follows is to-be-generated

public class EchoGetCall {
  var call : Call

  init(_ call: Call) {
    self.call = call
  }

  func perform(request: Echo_EchoRequest,
               callback:@escaping (CallResult, Echo_EchoResponse?) -> Void)
    -> Void {
      let requestMessageData = try! request.serializeProtobuf()
      let requestMetadata = Metadata()
      try! call.perform(message: requestMessageData,
                        metadata: requestMetadata)
      {(callResult) in
        print("Client received status \(callResult.statusCode) \(callResult.statusMessage!)")

        if let messageData = callResult.resultData {
          let responseMessage = try! Echo_EchoResponse(protobuf:messageData)
          callback(callResult, responseMessage)
        } else {
          callback(callResult, nil)
        }
      }
  }
}

public class EchoExpandCall {
  var call : Call

  init(_ call: Call) {
    self.call = call
  }

  func perform(request: Echo_EchoRequest,
               callback:@escaping (CallResult, Echo_EchoResponse?) -> Void)
    -> Void {
      let requestMessageData = try! request.serializeProtobuf()
      let requestMetadata = Metadata()
      try! call.startServerStreaming(message: requestMessageData,
                                     metadata: requestMetadata)
      {(callResult) in
        //print("Client received status \(callResult.statusCode): \(callResult.statusMessage!)")
      }
  }

  func receiveMessage(callback:@escaping (Echo_EchoResponse?) throws -> Void) throws {
    try call.receiveMessage() {(data) in
      if let data = data {
        if let responseMessage = try? Echo_EchoResponse(protobuf:data) {
          try callback(responseMessage)
        } else {
          try callback(nil)
        }
      } else {
        try callback(nil)
      }
    }
  }

}

public class EchoCollectCall {
  var call : Call

  init(_ call: Call) {
    self.call = call
  }

  func start(metadata:Metadata) throws {
    try self.call.start(metadata: metadata)
  }

  func receiveMessage(callback:@escaping (Echo_EchoResponse?) throws -> Void) throws {
    try call.receiveMessage() {(data) in
      guard
        let responseMessage = try? Echo_EchoResponse(protobuf:data)
        else {
          return
      }
      try callback(responseMessage)
    }
  }

  func sendMessage(message: Echo_EchoRequest) {
    let messageData = try! message.serializeProtobuf()
    _ = call.sendMessage(data:messageData)
  }

  func close(completion:@escaping (() -> Void)) throws {
    try call.close(completion:completion)
  }
}

public class EchoUpdateCall {
  var call : Call

  init(_ call: Call) {
    self.call = call
  }

  func start(metadata:Metadata) throws {
    try self.call.start(metadata: metadata)
  }

  func receiveMessage(callback:@escaping (Echo_EchoResponse?) throws -> Void) throws {
    try call.receiveMessage() {(data) in
      guard let data = data
        else {
          return
      }
      guard
        let responseMessage = try? Echo_EchoResponse(protobuf:data)
        else {
          return
      }
      try callback(responseMessage)
    }
  }

  func sendMessage(message: Echo_EchoRequest) {
    let messageData = try! message.serializeProtobuf()
    _ = call.sendMessage(data:messageData)
  }

  func close(completion:@escaping (() -> Void)) throws {
    try call.close(completion:completion)
  }
}

public class EchoService {
  public var channel: Channel

  public init(address: String) {
    channel = Channel(address:address)
  }

  public init(address: String, certificates: String?, host: String?) {
    channel = Channel(address:address, certificates:certificates, host:host)
  }

  func get() -> EchoGetCall {
    return EchoGetCall(channel.makeCall("/echo.Echo/Get"))
  }

  func expand() -> EchoExpandCall {
    return EchoExpandCall(channel.makeCall("/echo.Echo/Expand"))
  }

  func collect() -> EchoCollectCall {
    return EchoCollectCall(channel.makeCall("/echo.Echo/Collect"))
  }

  func update() -> EchoUpdateCall {
    return EchoUpdateCall(channel.makeCall("/echo.Echo/Update"))
  }
}
