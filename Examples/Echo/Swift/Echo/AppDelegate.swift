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
    //startServer(address:"localhost:8081")
  }

  func log(_ message: String) {
    print(message)
  }

  func startServer(address:String) {
    let fileDescriptorSet = FileDescriptorSet(filename:"echo.out")
    DispatchQueue.global().async {
      self.log("Server Starting")
      self.log("GRPC version " + gRPC.version())

      let server = gRPC.Server(address:address)
      server.start()

      while(true) {
        let (callError, completionType, requestHandler) = server.getNextRequest(timeout:1.0)
        if (callError != GRPC_CALL_OK) {
          self.log("Call error \(callError)")
          self.log("------------------------------")
        } else if (completionType == GRPC_OP_COMPLETE) {
          if let requestHandler = requestHandler {
            self.log("Received request to " + requestHandler.host()
              + " calling " + requestHandler.method()
              + " from " + requestHandler.caller())

            requestHandler.receiveMessage(initialMetadata:Metadata())
            {(requestBuffer) in
              if let requestBuffer = requestBuffer,
                let requestMessage = fileDescriptorSet.readMessage(name:"EchoRequest",
                                                                   proto:requestBuffer.data()) {
                requestMessage.forOneField(name:"text") {(field) in
                  let replyMessage = fileDescriptorSet.createMessage(name:"EchoResponse")!
                  let text = "echo " + field.string()
                  replyMessage.addField(name:"text", value:text)
                  requestHandler.sendResponse(message:ByteBuffer(data:replyMessage.serialize()),
                                              trailingMetadata:Metadata())
                }
              }
            }
          }
        } else if (completionType == GRPC_QUEUE_TIMEOUT) {
          // everything is fine
        } else if (completionType == GRPC_QUEUE_SHUTDOWN) {
          // we should stop
        }
      }
    }
  }
}

