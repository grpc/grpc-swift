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
import AppKit
import gRPC
import QuickProto

class EchoViewController : NSViewController, NSTextFieldDelegate {
  @IBOutlet weak var messageField: NSTextField!
  @IBOutlet weak var outputField: NSTextField!
  @IBOutlet weak var addressField: NSTextField!
  @IBOutlet weak var streamingButton: NSButton!

  private var streaming = false
  var client: Client!
  var call: Call!
  var fileDescriptorSet : FileDescriptorSet

  required init?(coder:NSCoder) {
    fileDescriptorSet = FileDescriptorSet(filename: "echo.out")
    super.init(coder:coder)
  }

  var enabled = false

  @IBAction func messageReturnPressed(sender: NSTextField) {
    if enabled {
      callServer(address:addressField.stringValue)
    }
  }

  @IBAction func addressReturnPressed(sender: NSTextField) {
    if (streaming) {
      print ("stop streaming")
      self.sendClose()
    }
  }

  @IBAction func buttonValueChanged(sender: NSButton) {
    print("button value changed \(sender)")
    if (streaming && (sender.intValue == 0)) {
      print ("stop streaming")
      self.sendClose()
    }

  }

  override func viewDidLoad() {
    gRPC.initialize()
  }

  override func viewDidAppear() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      self.enabled = true
    }
  }

  func log(_ message: String) {
    print(message)
  }

  func callServer(address:String) {
    gRPC.initialize()

    if (self.streamingButton.intValue == 0) {
      // NONSTREAMING

      // build the message
      if let requestMessage = self.fileDescriptorSet.createMessage(name:"EchoRequest") {
        requestMessage.addField(name:"text", value:self.messageField.stringValue)
        let requestHost = "foo.test.google.fr"
        let requestMethod = "/echo.Echo/Get"
        let requestMetadata = Metadata()

        client = Client(address:address)
        call = client.createCall(host: requestHost, method: requestMethod, timeout: 30.0)
        call.performNonStreamingCall(messageData: requestMessage.serialize(),
                                     metadata: requestMetadata)
        { (response) in
          self.log("Received status: \(response.status) " + response.statusDetails)
          if let messageData = response.messageData,
            let responseMessage = self.fileDescriptorSet.readMessage(name:"EchoResponse",
                                                                     proto:messageData) {
            responseMessage.forOneField(name:"text") {(field) in
              DispatchQueue.main.async {
                self.outputField.stringValue = field.string()
              }
            }
          } else {
            DispatchQueue.main.async {
              self.outputField.stringValue = "No message received. gRPC Status \(response.status) " + response.statusDetails
            }
          }
        }
      }
    }
    else {
      // STREAMING
      if (!streaming) {
        client = Client(address:address)
        call = client.createCall(host: "foo.test.google.fr",
                                 method: "/echo.Echo/Update",
                                 timeout: 600.0)
        let metadata = Metadata(["x-goog-api-key":"YOUR_API_KEY",
                                 "x-ios-bundle-identifier":Bundle.main.bundleIdentifier!])
        call.start(metadata:metadata)
        self.receiveMessage() // this should take a block in which we specify what to do
        streaming = true
      }
      self.sendMessage()
    }
  }

  func sendMessage() {
    let requestMessage = self.fileDescriptorSet.createMessage(name:"EchoRequest")!
    requestMessage.addField(name:"text", value:self.messageField.stringValue)
    let messageData = requestMessage.serialize()
    call.sendMessage(data:messageData)
  }

  func receiveMessage() {
    call.receiveMessage() {(data) in
      let responseMessage = self.fileDescriptorSet.readMessage(
        name:"EchoResponse",
        proto:data)!
      responseMessage.forOneField(name:"text") {(field) in
        DispatchQueue.main.async {
          self.outputField.stringValue = field.string()
        }
        self.receiveMessage()
      }
    }
  }

  func sendClose() {
    call.close() {
      self.streaming = false
    }
  }
}
