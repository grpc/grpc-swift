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
  @IBOutlet weak var TLSButton: NSButton!

  private var service : EchoService?
  private var updateCall: EchoUpdateCall?

  private var nowStreaming = false

  required init?(coder:NSCoder) {
    super.init(coder:coder)
  }

  private var enabled = false

  @IBAction func messageReturnPressed(sender: NSTextField) {
    if enabled {
      do {
        try callServer(address:addressField.stringValue)
      } catch (let error) {
        print(error)
      }
    }
  }

  @IBAction func addressReturnPressed(sender: NSTextField) {
    if (nowStreaming) {
      if let error = try? self.sendClose() {
        print(error)
      }
    }
  }

  @IBAction func buttonValueChanged(sender: NSButton) {
    if (nowStreaming && (sender.intValue == 0)) {
      if let error = try? self.sendClose() {
        print(error)
      }
    }
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

  func prepareService(address: String, host: String) {
    if (TLSButton.intValue == 0) {
      service = EchoService(address:address)
    } else {
      let certificateURL = Bundle.main.url(forResource: "ssl", withExtension: "crt")!
      let certificates = try! String(contentsOf: certificateURL)
      service = EchoService(address:address, certificates:certificates, host:host)
    }
    if let service = service {
      service.channel.host = host
    }
  }

  func callServer(address:String) throws -> Void {
    let requestMetadata = Metadata(["x-goog-api-key":"YOUR_API_KEY",
                                    "x-ios-bundle-identifier":Bundle.main.bundleIdentifier!])
    let host = "example.com"
    if (self.streamingButton.intValue == 0) {
      // NONSTREAMING
      if let fileDescriptorSet = FileDescriptorSet.from(filename:"echo.out"),
        let requestMessage = fileDescriptorSet.makeMessage("EchoRequest") {
        requestMessage.addField("text", value:self.messageField.stringValue)
        prepareService(address:address, host:host)
        if let service = service {
          let call = service.get()
          call.perform(request:requestMessage) {(callResult, response) in
            if let response = response {
              try! response.forOneField("text") {(field) in
                DispatchQueue.main.async {
                  self.outputField.stringValue = field.string()
                }
              }
            } else {
              DispatchQueue.main.async {
                self.outputField.stringValue = "No message received. gRPC Status \(callResult.statusCode): \(callResult.statusMessage)"
              }
            }
          }
        }
      }
    }
    else {
      // STREAMING
      if (!nowStreaming) {
        prepareService(address:address, host:host)
        guard let service = service else {
          return
        }
        updateCall = service.update()
        try updateCall!.start(metadata:requestMetadata)
        try self.receiveMessage()
        nowStreaming = true
      }
      self.sendMessage()
    }
  }

  func sendMessage() {
    if let fileDescriptorSet = FileDescriptorSet.from(filename:"echo.out") {
      let requestMessage = fileDescriptorSet.makeMessage("EchoRequest")!
      requestMessage.addField("text", value:self.messageField.stringValue)
      if let updateCall = updateCall {
        _ = updateCall.sendMessage(message:requestMessage)
      }
    }
  }

  func receiveMessage() throws -> Void {
    guard let updateCall = updateCall else {
      return
    }
    try updateCall.receiveMessage() {(responseMessage) in
      try self.receiveMessage() // prepare to receive the next message
      if let responseMessage = responseMessage {
        try responseMessage.forOneField("text") {(field) in
          DispatchQueue.main.async {
            self.outputField.stringValue = field.string()
          }
        }
      }
    }
  }

  func sendClose() throws {
    guard let updateCall = updateCall else {
      return
    }
    try updateCall.close() {
      self.nowStreaming = false
    }
  }
}



