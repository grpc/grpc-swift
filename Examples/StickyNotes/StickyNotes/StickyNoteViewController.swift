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

class StickyNoteViewController : NSViewController, NSTextFieldDelegate {
  @IBOutlet weak var messageField: NSTextField!
  @IBOutlet weak var imageView: NSImageView!

  @IBAction func messageReturnPressed(sender: NSTextField) {
    callServer(address:"localhost:8081")
  }

  func log(_ message: String) {
    print(message)
  }

  func callServer(address:String) {
    if let fileDescriptorSetProto =
      NSData(contentsOfFile:Bundle.main.path(forResource: "stickynote", ofType: "out")!) {
      // load a FileDescriptorSet that includes a descriptor for the message to be created
      let fileDescriptorSet = FileDescriptorSet(proto:fileDescriptorSetProto)

      // construct an internal representation of the message
      if let message = fileDescriptorSet.createMessage(name:"StickyNoteRequest") {
        message.addField(name:"message") {(field) in field.setString(self.messageField.stringValue)}
        message.display()

        // write the message as a protocol buffer
        let data = message.serialize()
        data.write(toFile: "SampleRequest.out", atomically: false)

        self.log("Client Starting")
        self.log("GRPC version " + gRPC.version())

        let host = "foo.test.google.fr"
        let message = gRPC.ByteBuffer(data:data)

        let i = 1
        let c = gRPC.Client(address:address)
        let method = "/messagepb.StickyNote/Get"

        let metadata = Metadata(pairs:[MetadataPair(key:"x", value:"xylophone"),
                                       MetadataPair(key:"y", value:"yu"),
                                       MetadataPair(key:"z", value:"zither")])

        let response = c.performRequest(host:host,
                                        method:method,
                                        message:message,
                                        metadata:metadata)

        if let initialMetadata = response.initialMetadata {
          for j in 0..<initialMetadata.count() {
            self.log("\(i): Received initial metadata -> " + initialMetadata.key(index:j) + " : " + initialMetadata.value(index:j))
          }
        }

        self.log("Received status: \(response.status) " + response.statusDetails)
        if let responsemessage = response.message {
          let data = responsemessage.data()
          if let message = fileDescriptorSet.readMessage(name:"StickyNoteResponse",
                                                         proto:data) {
            message.forOneField(name:"image") {(field) in
              let data = field.data()
              if let image = NSImage(data: data as Data) {
                self.imageView.image = image
              }
            }
          }
          if let trailingMetadata = response.trailingMetadata {
            for j in 0..<trailingMetadata.count() {
              self.log("\(i): Received trailing metadata -> " + trailingMetadata.key(index:j) + " : " + trailingMetadata.value(index:j))
            }
          }
          self.log("------------------------------")
          self.log("Client Stopped")
        }
      }
    }
  }
}


