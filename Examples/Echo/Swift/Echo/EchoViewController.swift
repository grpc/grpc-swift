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

class EchoViewController : NSViewController, NSTextFieldDelegate {
  @IBOutlet weak var messageField: NSTextField!
  @IBOutlet weak var sentOutputField: NSTextField!
  @IBOutlet weak var receivedOutputField: NSTextField!
  @IBOutlet weak var addressField: NSTextField!
  @IBOutlet weak var TLSButton: NSButton!
  @IBOutlet weak var callSelectButton: NSSegmentedControl!
  @IBOutlet weak var closeButton: NSButton!

  private var service : EchoService?

  private var expandCall: EchoExpandCall?
  private var collectCall: EchoCollectCall?
  private var updateCall: EchoUpdateCall?

  private var nowStreaming = false

  required init?(coder:NSCoder) {
    super.init(coder:coder)
  }

  private var enabled = false

  @IBAction func messageReturnPressed(sender: NSTextField) {
    if enabled {
      do {
        try callServer(address:addressField.stringValue,
                       host:"example.com")
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

  @IBAction func buttonValueChanged(sender: NSSegmentedControl) {
    if (nowStreaming) {
      if let error = try? self.sendClose() {
        print(error)
      }
    }
  }

  @IBAction func closeButtonPressed(sender: NSButton) {
    if (nowStreaming) {
      if let error = try? self.sendClose() {
        print(error)
      }
    }
  }

  override func viewDidLoad() {
    gRPC.initialize()
    closeButton.isEnabled = false
    // prevent the UI from trying to send messages until gRPC is initialized
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      self.enabled = true
    }
  }

  func displayMessageSent(_ message:String) {
    DispatchQueue.main.async {
      self.sentOutputField.stringValue = message
    }
  }

  func displayMessageReceived(_ message:String) {
    DispatchQueue.main.async {
      self.receivedOutputField.stringValue = message
    }
  }

  func prepareService(address: String, host: String) {
    if (service != nil) {
      return
    }
    if (TLSButton.intValue == 0) {
      service = EchoService(address:address)
    } else {
      let certificateURL = Bundle.main.url(forResource: "ssl",
                                           withExtension: "crt")!
      let certificates = try! String(contentsOf: certificateURL)
      service = EchoService(address:address, certificates:certificates, host:host)
    }
    if let service = service {
      service.channel.host = "example.com" // sample override
    }
  }

  func callServer(address:String, host:String) throws -> Void {
    prepareService(address:address, host:host)

    let requestMetadata = Metadata(["x-goog-api-key":"YOUR_API_KEY",
                                    "x-ios-bundle-identifier":Bundle.main.bundleIdentifier!])

    if (self.callSelectButton.selectedSegment == 0) {
      // NONSTREAMING
      if let service = service {
        let call = service.get()
        var requestMessage = Echo_EchoRequest()
        requestMessage.text = self.messageField.stringValue
        self.displayMessageSent(requestMessage.text)
        call.perform(request:requestMessage) {(callResult, response) in
          if let response = response {
            self.displayMessageReceived(response.text)
          } else {
            self.displayMessageReceived("No message received. gRPC Status \(callResult.statusCode): \(callResult.statusMessage)")
          }
        }
      }
    }
    else if (self.callSelectButton.selectedSegment == 1) {
      // STREAMING EXPAND
      if (!nowStreaming) {
        guard let service = service else {
          return
        }
        expandCall = service.expand()
        var requestMessage = Echo_EchoRequest()
        requestMessage.text = self.messageField.stringValue
        self.displayMessageSent(requestMessage.text)
        try expandCall!.perform(request:requestMessage) {(callResult, response) in
        }
        try! self.receiveExpandMessage()
      }
    }
    else if (self.callSelectButton.selectedSegment == 2) {
      // STREAMING COLLECT
      if (!nowStreaming) {
        guard let service = service else {
          return
        }
        collectCall = service.collect()
        try collectCall!.start(metadata:requestMetadata)
        try self.receiveCollectMessage()
        nowStreaming = true
        closeButton.isEnabled = true
      }
      self.sendCollectMessage()
    }
    else if (self.callSelectButton.selectedSegment == 3) {
      // STREAMING UPDATE
      if (!nowStreaming) {
        guard let service = service else {
          return
        }
        updateCall = service.update()
        try updateCall!.start(metadata:requestMetadata)
        try self.receiveUpdateMessage()
        nowStreaming = true
        closeButton.isEnabled = true
      }
      self.sendUpdateMessage()
    }
  }

  func receiveExpandMessage() throws -> Void {
    guard let expandCall = expandCall else {
      return
    }
    try expandCall.receiveMessage() {(responseMessage) in
      if let responseMessage = responseMessage {
        try self.receiveExpandMessage() // prepare to receive the next message
        self.displayMessageReceived(responseMessage.text)
      } else {
        print("expand closed")
      }
    }
  }

  func sendCollectMessage() {
    if let collectCall = collectCall {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = self.messageField.stringValue
      self.displayMessageSent(requestMessage.text)
      _ = collectCall.sendMessage(message:requestMessage)
    }
  }

  func receiveCollectMessage() throws -> Void {
    guard let collectCall = collectCall else {
      return
    }
    try collectCall.receiveMessage() {(responseMessage) in
      if let responseMessage = responseMessage {
        self.displayMessageReceived(responseMessage.text)
      } else {
        print("collect closed")
        self.nowStreaming = false
        self.closeButton.isEnabled = false
      }
    }
  }

  func sendUpdateMessage() {
    if let updateCall = updateCall {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = self.messageField.stringValue
      self.displayMessageSent(requestMessage.text)
      _ = updateCall.sendMessage(message:requestMessage)
    }
  }

  func receiveUpdateMessage() throws -> Void {
    guard let updateCall = updateCall else {
      return
    }
    try updateCall.receiveMessage() {(responseMessage) in
      try self.receiveUpdateMessage() // prepare to receive the next message
      if let responseMessage = responseMessage {
        DispatchQueue.main.async {
          self.receivedOutputField.stringValue = responseMessage.text
        }
      } else {
        print("update closed")
        self.nowStreaming = false
        self.closeButton.isEnabled = false
      }
    }
  }

  func sendClose() throws {
    if let updateCall = updateCall {
      try updateCall.close() {
        self.updateCall = nil
        self.nowStreaming = false
        self.closeButton.isEnabled = false
      }
    }
    if let collectCall = collectCall {
      try collectCall.close() {
        self.collectCall = nil
        self.nowStreaming = false
        self.closeButton.isEnabled = false
      }
    }
  }
}



