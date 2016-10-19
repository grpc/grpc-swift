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
import QuickProto

// all code that follows is to-be-generated

public class EchoGetCall {
  var call : Call

  init(_ call: Call) {
    self.call = call
  }

  func perform(request: Message, callback:@escaping (CallResult, Message?) -> Void) -> Void {
    let requestMessageData = request.data()
    let requestMetadata = Metadata()
    try! call.perform(message: requestMessageData,
                      metadata: requestMetadata)
    {(callResult) in
      print("Client received status \(callResult.statusCode): \(callResult.statusMessage!)")

      if let messageData = callResult.resultData,
        let fileDescriptorSet = FileDescriptorSet.from(filename:"echo.out"),
        let responseMessage = fileDescriptorSet.readMessage("EchoResponse",
                                                            data:messageData) {

        callback(callResult, responseMessage)
      } else {
        callback(callResult, nil)
      }
    }
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

  func receiveMessage(callback:@escaping (Message?) throws -> Void) throws {
    try call.receiveMessage() {(data) in
      guard
        let fileDescriptorSet = FileDescriptorSet.from(filename:"echo.out"),
        let responseMessage = fileDescriptorSet.readMessage("EchoResponse", data:data)
        else {
          return
      }
      try callback(responseMessage)
    }
  }

  func sendMessage(message:Message) {
    let messageData = message.data()
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

  func update() -> EchoUpdateCall {
    return EchoUpdateCall(channel.makeCall("/echo.Echo/Update"))
  }
}
