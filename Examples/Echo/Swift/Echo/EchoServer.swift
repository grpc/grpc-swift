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

class EchoServer {
  private var address: String
  private var server: Server

  init(address:String, secure:Bool) {
    gRPC.initialize()
    self.address = address
    if secure {
      let certificateURL = Bundle.main.url(forResource: "ssl", withExtension: "crt")!
      let certificate = try! String(contentsOf: certificateURL)
      let keyURL = Bundle.main.url(forResource: "ssl", withExtension: "key")!
      let key = try! String(contentsOf: keyURL)
      self.server = gRPC.Server(address:address, key:key, certs:certificate)
    } else {
      self.server = gRPC.Server(address:address)
    }
  }

  func start() {
    let fileDescriptorSet = FileDescriptorSet(filename:"echo.out")
    print("Server Starting")
    print("GRPC version " + gRPC.version())

    server.run {(requestHandler) in
      print("Received request to " + requestHandler.host
        + " calling " + requestHandler.method
        + " from " + requestHandler.caller)

      // NONSTREAMING
      if (requestHandler.method == "/echo.Echo/Get") {
        do {
          try requestHandler.receiveMessage(initialMetadata:Metadata()) {(requestData) in
            if let requestData = requestData,
              let requestMessage = fileDescriptorSet.readMessage("EchoRequest", data:requestData) {
              try requestMessage.forOneField("text") {(field) in
                let replyMessage = fileDescriptorSet.makeMessage("EchoResponse")!
                replyMessage.addField("text", value:"Swift nonstreaming echo " + field.string())
                try requestHandler.sendResponse(message:replyMessage.data(),
                                                statusCode: 0,
                                                statusMessage: "OK",
                                                trailingMetadata:Metadata())
              }
            }
          }
        } catch (let callError) {
          print("grpc error: \(callError)")
        }
      }

      // STREAMING
      if (requestHandler.method == "/echo.Echo/Update") {
        do {
          try requestHandler.sendMetadata(initialMetadata:Metadata()) {
            // wait for messages and handle them
            try self.receiveMessage(fileDescriptorSet:fileDescriptorSet,
                                    requestHandler:requestHandler)
            // concurrently wait for a close message
            try requestHandler.receiveClose() {
              try requestHandler.sendStatus(statusCode: 0,
                                            statusMessage:"OK",
                                            trailingMetadata: Metadata())
              {
                requestHandler.shutdown()
              }
            }
          }
        } catch (let callError) {
          print("grpc error: \(callError)")
        }
      }
    }
  }

  func receiveMessage(fileDescriptorSet: FileDescriptorSet, requestHandler: Handler) throws -> Void {
    try requestHandler.receiveMessage() {(requestData) in
      if let requestData = requestData {
        if let requestMessage = fileDescriptorSet.readMessage("EchoRequest", data:requestData) {
          try requestMessage.forOneField("text") {(field) in
            let replyMessage = fileDescriptorSet.makeMessage("EchoResponse")!
            replyMessage.addField("text", value:"Swift streaming echo " + field.string())
            try requestHandler.sendResponse(message:replyMessage.data()) {
              // after we've sent our response, prepare to handle another message
              try self.receiveMessage(fileDescriptorSet:fileDescriptorSet, requestHandler:requestHandler)
            }
          }
        }
      } else {
        // if we get an empty message (requestData == nil), we close the connection
        try requestHandler.sendStatus(statusCode: 0,
                                      statusMessage: "OK",
                                      trailingMetadata: Metadata())
        {
          requestHandler.shutdown()
        }
      }
    }
  }
}
