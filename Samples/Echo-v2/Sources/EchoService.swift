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

enum EchoResult {
  case Response(r: Echo_EchoResponse)
  case CallResult(c: CallResult)
  case Error(s: String)
}

public class EchoGetCall {
  var call : Call

  init(_ call: Call) {
    self.call = call
  }

  // Call this with the message to send,
  // the callback will be called after the request is received.
  func perform(request: Echo_EchoRequest,
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

public class EchoExpandCall {
  var call : Call

  init(_ call: Call) {
    self.call = call
  }

  // Call this once with the message to send,
  // the callback will be called after the request is initiated.
  func perform(request: Echo_EchoRequest,
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

  func Recv() -> EchoResult {
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

public class EchoCollectCall {
  var call : Call

  init(_ call: Call) {
    self.call = call
  }

  // Call this to start a call.
  func start(metadata:Metadata, completion:@escaping (() -> Void)) throws {
    try self.call.start(metadata: metadata, completion:completion)
  }

  // Call this to send each message in the request stream.
  func Send(_ message: Echo_EchoRequest) {
    let messageData = try! message.serializeProtobuf()
    _ = call.sendMessage(data:messageData)
  }

  func CloseAndRecv() -> EchoResult {
    let done = NSCondition()
    var result : EchoResult!

    try! self.receiveMessage() {(responseMessage) in
      print("received")
      if let responseMessage = responseMessage {
        result = EchoResult.Response(r: responseMessage)
      } else {
        result = EchoResult.Error(s: "INVALID RESPONSE")
      }
      done.lock()
      done.signal()
      done.unlock()
    }

    try! self.close(completion:{})
    done.lock()
    done.wait()
    done.unlock()
    return result
  }

  // Call this to receive a message.
  // The callback will be called when a message is received.
  // call this again from the callback to wait for another message.
  func receiveMessage(callback:@escaping (Echo_EchoResponse?) throws -> Void)
    throws {
      print("receiving message")
      try call.receiveMessage() {(data) in
        guard
          let responseMessage = try? Echo_EchoResponse(protobuf:data)
          else {
            return
        }
        try callback(responseMessage)
      }
  }

  func close(completion:@escaping (() -> Void)) throws {
    print("closing")
    try call.close(completion:completion)
  }
}

public class EchoUpdateCall {
  var call : Call

  init(_ call: Call) {
    self.call = call
  }

  func start(metadata:Metadata, completion:@escaping (() -> Void)) throws {
    try self.call.start(metadata: metadata, completion:completion)
  }

  func receiveMessage(callback:@escaping (Echo_EchoResponse?) throws -> Void) throws {
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

  func Recv() -> EchoResult {
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

  func Send(message:Echo_EchoRequest) {
    let messageData = try! message.serializeProtobuf()
    _ = call.sendMessage(data:messageData)
  }

  func CloseSend() {
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

public class EchoService {
  public var channel: Channel

  public init(address: String) {
    channel = Channel(address:address)
  }

  public init(address: String, certificates: String?, host: String?) {
    channel = Channel(address:address, certificates:certificates, host:host)
  }

  func get(_ requestMessage: Echo_EchoRequest) -> EchoResult {
    let call = EchoGetCall(channel.makeCall("/echo.Echo/Get"))
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

  func expand(_ requestMessage: Echo_EchoRequest) -> EchoExpandCall {
    let call = EchoExpandCall(channel.makeCall("/echo.Echo/Expand"))
    call.perform(request:requestMessage) {response in }
    return call
  }

  func collect() -> EchoCollectCall {
    let call = EchoCollectCall(channel.makeCall("/echo.Echo/Collect"))
    try! call.start(metadata:Metadata(), completion:{})
    return call
  }

  func update() -> EchoUpdateCall {
    let call = EchoUpdateCall(channel.makeCall("/echo.Echo/Update"))
    try! call.start(metadata:Metadata(), completion:{})
    return call
  }
}
