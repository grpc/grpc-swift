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
  var client: Client?
  var call: Call?
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
      client = Client(address:address)
      self.client!.completionQueue.run() {}

      DispatchQueue.global().async {
        // build the message
        if let requestMessage = self.fileDescriptorSet.createMessage(name:"EchoRequest") {
          requestMessage.addField(name:"text", value:self.messageField.stringValue)

          let requestHost = "foo.test.google.fr"
          let requestMethod = "/echo.Echo/Get"
          let requestBuffer = ByteBuffer(data:requestMessage.serialize())
          let requestMetadata = Metadata()

          _ = self.client!.performRequest(host:requestHost,
                                          method:requestMethod,
                                          message:requestBuffer,
                                          metadata:requestMetadata)
          { (response) in
            self.log("Received status: \(response.status) " + response.statusDetails)

            if let responseBuffer = response.message,
              let responseMessage = self.fileDescriptorSet.readMessage(
                name:"EchoResponse",
                proto:responseBuffer.data()) {
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
    }
    else {
      if (!streaming) {
        client = Client(address:address)
        self.client!.completionQueue.run() {}

        call = client?.createCall(host: "foo.test.google.fr",
                                  method: "/echo.Echo/Update",
                                  timeout: 600.0)

        self.sendInitialMetadata()
        self.receiveInitialMetadata()
        self.receiveStatus()
        self.receiveMessage()
        streaming = true
      }
      self.sendMessage()
    }
  }

  func sendInitialMetadata() {
    let metadata = Metadata(
      pairs:[MetadataPair(key:"x-goog-api-key", value:"YOUR_API_KEY"),
             MetadataPair(key:"x-ios-bundle-identifier", value:Bundle.main.bundleIdentifier!)])
    let operation_sendInitialMetadata = Operation_SendInitialMetadata(metadata:metadata);
    let operations = OperationGroup(call:call!, operations:[operation_sendInitialMetadata])
    { (event) in
      if (event.type == GRPC_OP_COMPLETE) {
        print("call status \(event.type) \(event.tag)")
      } else {
        return
      }
    }

    let call_error = client!.perform(call:call!, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error: \(call_error)")
    }
  }

  func receiveInitialMetadata() {
    let operation_receiveInitialMetadata = Operation_ReceiveInitialMetadata()
    let operations = OperationGroup(call:call!, operations:[operation_receiveInitialMetadata])
    { (event) in
      print("receive initial metadata status \(event.type) \(event.tag)")
      let initialMetadata = operation_receiveInitialMetadata.metadata()
      for j in 0..<initialMetadata.count() {
        print("Received initial metadata -> " + initialMetadata.key(index:j) + " : " + initialMetadata.value(index:j))
      }
    }
    let call_error = client!.perform(call:call!, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error \(call_error)")
    }
  }

  func sendMessage() {
    let requestMessage = self.fileDescriptorSet.createMessage(name:"EchoRequest")!
    requestMessage.addField(name:"text", value:self.messageField.stringValue)
    let messageData = requestMessage.serialize()
    let messageBuffer = ByteBuffer(data:messageData)
    let operation_sendMessage = Operation_SendMessage(message:messageBuffer)
    let operations = OperationGroup(call:call!, operations:[operation_sendMessage])
    { (event) in
      print("send message call status \(event.type) \(event.tag)")
    }
    let call_error = client!.perform(call:call!, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error \(call_error)")
    }
  }

  func receiveStatus() {
    let operation_receiveStatus = Operation_ReceiveStatusOnClient()
    let operations = OperationGroup(call:call!,
                                    operations:[operation_receiveStatus])
    { (event) in
      print("receive status call status \(event.type) \(event.tag)")
      print("status = \(operation_receiveStatus.status()), \(operation_receiveStatus.statusDetails())")
    }
    let call_error = client!.perform(call:call!, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error \(call_error)")
    }
  }

  func receiveMessage() {
    let operation_receiveMessage = Operation_ReceiveMessage()
    let operations = OperationGroup(call:call!, operations:[operation_receiveMessage])
    { (event) in
      print("call status \(event.type) \(event.tag)")
      if let messageBuffer = operation_receiveMessage.message() {
        let responseMessage = self.fileDescriptorSet.readMessage(
          name:"EchoResponse",
          proto:messageBuffer.data())!
        responseMessage.forOneField(name:"text") {(field) in
          DispatchQueue.main.async {
            self.outputField.stringValue = field.string()
          }
          self.receiveMessage()
        }
      }
    }
    let call_error = client!.perform(call:call!, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error \(call_error)")
    }
  }

  func sendClose() {
    let operation_sendCloseFromClient = Operation_SendCloseFromClient()
    let operations = OperationGroup(call:call!, operations:[operation_sendCloseFromClient])
    { (event) in
      print("send close call status \(event.type) \(event.tag)")
      self.streaming = false
    }
    let call_error = client!.perform(call:call!, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error \(call_error)")
    }
  }
}


