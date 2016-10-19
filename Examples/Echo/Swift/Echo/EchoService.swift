//
//  EchoService.swift
//  Echo
//
//  Created by Tim Burks on 10/18/16.
//  Copyright © 2016 Google. All rights reserved.
//

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
