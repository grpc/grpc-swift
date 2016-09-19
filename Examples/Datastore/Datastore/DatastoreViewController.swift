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

let APIKey = "AIzaSyDBqO88sO7iXScpFzmP7nOdamVYi7Y2Lbs"
let Host = "datastore.googleapis.com"

class DatastoreViewController : NSViewController, NSTextFieldDelegate {
  @IBOutlet weak var messageField: NSTextField!
  @IBOutlet weak var outputField: NSTextField!


  private var fileDescriptorSet : FileDescriptorSet
  private var client: Client?
  private var call: Call?

  required init?(coder:NSCoder) {
    fileDescriptorSet = FileDescriptorSet(filename: "descriptors.out")
    super.init(coder:coder)
  }

  var enabled = false

  @IBAction func messageReturnPressed(sender: NSTextField) {
    if enabled {
      callServer(address:Host)
    }
  }

  @IBAction func addressReturnPressed(sender: NSTextField) {
  }

  @IBAction func buttonValueChanged(sender: NSButton) {
  }

  override func viewDidLoad() {
    gRPC.initialize()
  }

  override func viewDidAppear() {
    // prevent the UI from trying to send messages until gRPC is initialized
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      self.enabled = true
    }
  }

  func createClient(address: String, host: String) {
    client = Client(address:address, certificates:nil, host:nil)
  }

  func callServer(address:String) {
    let requestHost = Host
    let requestMetadata = Metadata(["x-goog-api-key":APIKey,
                                    "x-ios-bundle-identifier":Bundle.main.bundleIdentifier!])

    // NONSTREAMING
    if let requestMessage = self.fileDescriptorSet.createMessage("RunQueryRequest") {
      requestMessage.addField("project_id", value:"hello-86")
      let gqlQuery = self.fileDescriptorSet.createMessage("GqlQuery")
      gqlQuery?.addField("query_string", value:"select * from Person")
      requestMessage.addField("gql_query", value:gqlQuery)
      let requestMessageData = requestMessage.data()

      let check = self.fileDescriptorSet.readMessage("RunQueryRequest", data:requestMessageData)
      check?.display()

      createClient(address:address, host:requestHost)
      guard let client = client else {
        return
      }
      call = client.createCall(host: requestHost,
                               method: "/google.datastore.v1.Datastore/RunQuery",
                               timeout: 30.0)
      guard let call = call else {
        return
      }
      _ = call.performNonStreamingCall(messageData: requestMessageData,
                                       metadata: requestMetadata)
      { (status, statusDetails, messageData, initialMetadata, trailingMetadata) in
        print("Received status: \(status): \(statusDetails)")
        if let messageData = messageData,
          let responseMessage = self.fileDescriptorSet.readMessage("RunQueryResponse",
                                                                   data:messageData) {
          responseMessage.display()
          responseMessage.forOneField("text") {(field) in
            DispatchQueue.main.async {
              self.outputField.stringValue = field.string()
            }
          }
        } else {
          DispatchQueue.main.async {
            self.outputField.stringValue = "No message received. gRPC Status \(status): \(statusDetails)"
          }
        }
      }

    }
  }
}
