//
//  EchoServer.swift
//  Echo
//
//  Created by Tim Burks on 9/8/16.
//  Copyright © 2016 Google. All rights reserved.
//

import Foundation
import gRPC
import QuickProto

class EchoServer {
  private var address: String

  init(address:String) {
    self.address = address
  }

  func start() {
    let fileDescriptorSet = FileDescriptorSet(filename:"echo.out")
    print("Server Starting")
    print("GRPC version " + gRPC.version())

    let server = gRPC.Server(address:address)

    server.run {(requestHandler) in
      print("Received request to " + requestHandler.host()
        + " calling " + requestHandler.method()
        + " from " + requestHandler.caller())

      // NONSTREAMING
      if (requestHandler.method() == "/echo.Echo/Get") {
        requestHandler.receiveMessage(initialMetadata:Metadata())
        {(requestData) in
          if let requestData = requestData,
            let requestMessage =
            fileDescriptorSet.readMessage("EchoRequest", data: requestData) {
            requestMessage.forOneField("text") {(field) in
              let replyMessage = fileDescriptorSet.createMessage("EchoResponse")!
              replyMessage.addField("text", value:"Swift nonstreaming echo " + field.string())
              requestHandler.sendResponse(message:replyMessage.serialize(),
                                          trailingMetadata:Metadata())
            }
          }
        }
      }

      // STREAMING
      if (requestHandler.method() == "/echo.Echo/Update") {
        requestHandler.sendMetadata(
          initialMetadata: Metadata(),
          completion: {

            self.handleMessage(
              fileDescriptorSet: fileDescriptorSet,
              requestHandler: requestHandler)

            // we seem to never get this, but I'm told it's what we're supposed to do
            requestHandler.receiveClose() {
              requestHandler.sendStatus(trailingMetadata: Metadata(), completion: {
                print("status sent")
                requestHandler.shutdown()
              })
            }
          }
        )
      }
    }
  }

  func handleMessage(fileDescriptorSet: FileDescriptorSet,
                     requestHandler: Handler) {
    requestHandler.receiveMessage()
      {(requestData) in
        if let requestData = requestData,
          let requestMessage = fileDescriptorSet.readMessage("EchoRequest", data:requestData) {
          requestMessage.forOneField("text") {(field) in
            let replyMessage = fileDescriptorSet.createMessage("EchoResponse")!
            replyMessage.addField("text", value:"Swift streaming echo " + field.string())
            requestHandler.sendResponse(message:replyMessage.serialize()) {
              // after we've sent our response, prepare to handle another message
              self.handleMessage(fileDescriptorSet:fileDescriptorSet, requestHandler:requestHandler)
            }
          }
        } else {
          // if we get an empty message (nil buffer), we close the connection
          requestHandler.sendStatus(trailingMetadata: Metadata(), completion: {
            print("status sent")
            requestHandler.shutdown()
          })
        }
    }
  }
}
