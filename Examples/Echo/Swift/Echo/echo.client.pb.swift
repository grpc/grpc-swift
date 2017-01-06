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

// all code that follows is to-be-generated

import Foundation
import gRPC

// this is probably going to go.
public enum EchoResult {
  case Response(r: Echo_EchoResponse)
  // these last two should be merged
  case CallResult(c: CallResult)
  case Error(s: String)
}

//
// Unary GET
//
public class Echo_EchoGetCall {
  var call : Call

  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("/echo.Echo/Get")
  }

  // Call this with the message to send,
  // the callback will be called after the request is received.
  fileprivate func perform(request: Echo_EchoRequest,
                           callback:@escaping (EchoResult) -> Void)
    -> Void {
      let requestMessageData = try! request.serializeProtobuf()
      let requestMetadata = Metadata()
      try! call.perform(message: requestMessageData,
                        metadata: requestMetadata)
      {(callResult) in
        print("Client received status \(callResult.statusCode) \(callResult.statusMessage!)")
        if let messageData = callResult.resultData {
          let responseMessage = try! Echo_EchoResponse(protobuf:messageData)
          callback(EchoResult.Response(r: responseMessage))
        } else {
          callback(EchoResult.CallResult(c: callResult))
        }
      }
  }
}

//
// Server-streaming EXPAND
//
public class Echo_EchoExpandCall {
  var call : Call

  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("/echo.Echo/Expand")
  }

  // Call this once with the message to send,
  // the callback will be called after the request is initiated.
  fileprivate func perform(request: Echo_EchoRequest,
                           callback:@escaping (CallResult) -> Void)
    -> Void {
      let requestMessageData = try! request.serializeProtobuf()
      let requestMetadata = Metadata()
      try! call.startServerStreaming(message: requestMessageData,
                                     metadata: requestMetadata)
      {(callResult) in
        callback(callResult)
      }
  }

  // Call this to wait for a result.
  // BLOCKING
  public func Receive() -> EchoResult {
    let done = NSCondition()
    var result : EchoResult!
    try! call.receiveMessage() {(data) in
      if let data = data {
        if let responseMessage = try? Echo_EchoResponse(protobuf:data) {
          result = EchoResult.Response(r: responseMessage)
        } else {
          result = EchoResult.Error(s: "INVALID RESPONSE")
        }
      } else {
        result = EchoResult.Error(s: "EOM")
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    return result
  }
}

//
// Client-streaming COLLECT
//
public class Echo_EchoCollectCall {
  var call : Call

  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("/echo.Echo/Collect")
  }

  // Call this to start a call.
  fileprivate func start(metadata:Metadata, completion:@escaping (() -> Void)) throws {
    try self.call.start(metadata: metadata, completion:completion)
  }

  // Call this to send each message in the request stream.
  public func Send(_ message: Echo_EchoRequest) {
    let messageData = try! message.serializeProtobuf()
    _ = call.sendMessage(data:messageData)
  }

  // Call this to close the connection and wait for a response.
  // BLOCKING
  public func CloseAndReceive() -> EchoResult {
    let done = NSCondition()
    var result : EchoResult!

    do {
      try self.receiveMessage() {(responseMessage) in
        if let responseMessage = responseMessage {
          result = EchoResult.Response(r: responseMessage)
        } else {
          result = EchoResult.Error(s: "INVALID RESPONSE")
        }
        done.lock()
        done.signal()
        done.unlock()
      }
    } catch (let error) {
      print("ERROR A: \(error)")
    }
    do {
      try call.close(completion:{
        print("closed")
      })
    } catch (let error) {
      print("ERROR B: \(error)")
    }

    done.lock()
    done.wait()
    done.unlock()

    return result
  }

  // Call this to receive a message.
  // The callback will be called when a message is received.
  // call this again from the callback to wait for another message.
  fileprivate func receiveMessage(callback:@escaping (Echo_EchoResponse?) throws -> Void)
    throws {
      try call.receiveMessage() {(data) in
        guard let data = data else {
          try callback(nil)
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

}

//
// Bidirectional-streaming UPDATE
//
public class Echo_EchoUpdateCall {
  var call : Call

  fileprivate init(_ channel: Channel) {
    self.call = channel.makeCall("/echo.Echo/Update")
  }

  fileprivate func start(metadata:Metadata, completion:@escaping (() -> Void)) throws {
    try self.call.start(metadata: metadata, completion:completion)
  }

  fileprivate func receiveMessage(callback:@escaping (Echo_EchoResponse?) throws -> Void) throws {
    try call.receiveMessage() {(data) in
      if let data = data {
        if let responseMessage = try? Echo_EchoResponse(protobuf:data) {
          try callback(responseMessage)
        } else {
          try callback(nil) // error, bad data
        }
      } else {
        try callback(nil)
      }
    }
  }

  public func Receive() -> EchoResult {
    let done = NSCondition()
    var result : EchoResult!
    try! self.receiveMessage() {responseMessage in
      if let responseMessage = responseMessage {
        result = EchoResult.Response(r: responseMessage)
      } else {
        result = EchoResult.Error(s: "EOM")
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    return result
  }

  public func Send(message:Echo_EchoRequest) {
    let messageData = try! message.serializeProtobuf()
    _ = call.sendMessage(data:messageData)
  }

  public func CloseSend() {
    let done = NSCondition()
    try! call.close() {
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
  }
}

// Call methods of this class to make API calls.
public class Echo_EchoService {
  public var channel: Channel

  public init(address: String) {
    gRPC.initialize()
    channel = Channel(address:address)
  }

  public init(address: String, certificates: String?, host: String?) {
    gRPC.initialize()
    channel = Channel(address:address, certificates:certificates, host:host)
  }

  // Synchronous. Unary.
  public func get(_ requestMessage: Echo_EchoRequest) -> EchoResult {
    let call = Echo_EchoGetCall(channel)
    let done = NSCondition()
    var finalResult : EchoResult!
    call.perform(request:requestMessage) {(result) in
      finalResult = result
      done.lock()
      done.signal()
      done.unlock()
    }
    done.lock()
    done.wait()
    done.unlock()
    return finalResult
  }

  // Asynchronous. Server-streaming.
  // Send the initial message.
  // Use methods on the returned object to get streamed responses.
  public func expand(_ requestMessage: Echo_EchoRequest) -> Echo_EchoExpandCall {
    let call = Echo_EchoExpandCall(channel)
    call.perform(request:requestMessage) {response in }
    return call
  }

  // Asynchronous. Client-streaming.
  // Use methods on the returned object to stream messages and
  // to close the connection and wait for a final response.
  public func collect() -> Echo_EchoCollectCall {
    let call = Echo_EchoCollectCall(channel)
    try! call.start(metadata:Metadata(), completion:{})
    return call
  }

  // Asynchronous. Bidirectional-streaming.
  // Use methods on the returned object to stream messages,
  // to wait for replies, and to close the connection.
  public func update() -> Echo_EchoUpdateCall {
    let call = Echo_EchoUpdateCall(channel)
    try! call.start(metadata:Metadata(), completion:{})
    return call
  }
}
