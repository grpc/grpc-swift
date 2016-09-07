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
import Cocoa
import gRPC
import QuickProto

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

  @IBOutlet weak var window: NSWindow!

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    gRPC.initialize()
    startServer(address:"localhost:8081")
  }

  func startServer(address:String) {
    let fileDescriptorSet = FileDescriptorSet(filename:"echo.out")
    print("Server Starting")
    print("GRPC version " + gRPC.version())

    let server = gRPC.Server(address:address)

    server.run {(requestHandler) in
      print("Received request to " + requestHandler.host()
        + " calling " + requestHandler.method()
        + " from " + requestHandler.caller())

      if (requestHandler.method() == "/echo.Echo/Get") {
        requestHandler.receiveMessage(initialMetadata:Metadata())
        {(requestBuffer) in
          if let requestBuffer = requestBuffer,
            let requestMessage =
            fileDescriptorSet.readMessage(name:"EchoRequest",
                                          proto:requestBuffer.data()) {
            requestMessage.forOneField(name:"text") {(field) in
              let replyMessage = fileDescriptorSet.createMessage(name:"EchoResponse")!
              let text = "Swift nonstreaming echo " + field.string()
              replyMessage.addField(name:"text", value:text)
              requestHandler.sendResponse(message:ByteBuffer(data:replyMessage.serialize()),
                                          trailingMetadata:Metadata())
            }
          }
        }
      }

      if (requestHandler.method() == "/echo.Echo/Update") {
        requestHandler.sendMetadata(
          initialMetadata: Metadata(),
          completion: {
            self.handleMessage(
              fileDescriptorSet: fileDescriptorSet,
              requestHandler: requestHandler)
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
      {(requestBuffer) in
        if let requestBuffer = requestBuffer,
          let requestMessage =
          fileDescriptorSet.readMessage(name:"EchoRequest",
                                        proto:requestBuffer.data()) {
          requestMessage.forOneField(name:"text") {(field) in
            let replyMessage = fileDescriptorSet.createMessage(name:"EchoResponse")!
            let text = "Swift streaming echo " + field.string()
            replyMessage.addField(name:"text", value:text)
            requestHandler.sendResponse(
            message:ByteBuffer(data:replyMessage.serialize())) {
              self.handleMessage(fileDescriptorSet:fileDescriptorSet, requestHandler:requestHandler)
            }
          }
        } else {
          // an empty message means close the connection
          requestHandler.sendStatus(trailingMetadata: Metadata(), completion: {
            print("status sent")
            requestHandler.shutdown()
          })
        }
    }
  }
}
