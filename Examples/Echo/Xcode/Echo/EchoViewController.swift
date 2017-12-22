/*
 * Copyright 2016, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
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

  private var service : Echo_EchoService?

  private var expandCall: Echo_EchoExpandCall?
  private var collectCall: Echo_EchoCollectCall?
  private var updateCall: Echo_EchoUpdateCall?

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
      do {
        try self.sendClose()
      } catch (let error) {
        print(error)
      }
    }
    // invalidate the service
    service = nil
  }

  @IBAction func buttonValueChanged(sender: NSSegmentedControl) {
    if (nowStreaming) {
      do {
        try self.sendClose()
      } catch (let error) {
        print(error)
      }
    }
  }

  @IBAction func closeButtonPressed(sender: NSButton) {
    if (nowStreaming) {
      do {
        try self.sendClose()
      } catch (let error) {
        print(error)
      }
    }
  }

  override func viewDidLoad() {
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
      service = Echo_EchoService(address:address, secure:false)
    } else {
      let certificateURL = Bundle.main.url(forResource: "ssl",
                                           withExtension: "crt")!
      let certificates = try! String(contentsOf: certificateURL)
      service = Echo_EchoService(address:address, certificates:certificates, host:host)
    }
    if let service = service {
      service.host = "example.com" // sample override
      service.metadata = Metadata(["x-goog-api-key":"YOUR_API_KEY",
                                   "x-ios-bundle-identifier":Bundle.main.bundleIdentifier!])
    }
  }

  func callServer(address:String, host:String) throws -> Void {
    prepareService(address:address, host:host)
    guard let service = service else {
      return
    }
    if (self.callSelectButton.selectedSegment == 0) {
      // NONSTREAMING
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = self.messageField.stringValue
      self.displayMessageSent(requestMessage.text)
      _ = try service.get(requestMessage) {responseMessage, callResult in
        if let responseMessage = responseMessage {
          self.displayMessageReceived(responseMessage.text)
        } else  {
          self.displayMessageReceived("No message received. \(callResult)")
        }
      }
    }
    else if (self.callSelectButton.selectedSegment == 1) {
      // STREAMING EXPAND
      if (!nowStreaming) {
        do {
          var requestMessage = Echo_EchoRequest()
          requestMessage.text = self.messageField.stringValue
          self.expandCall = try service.expand(requestMessage) {call in
            print("Started expand \(call)")
          }
          try self.receiveExpandMessages()
          self.displayMessageSent(requestMessage.text)
        } catch (let error) {
          self.displayMessageReceived("No message received. \(error)")
        }
      }
    }
    else if (self.callSelectButton.selectedSegment == 2) {
      // STREAMING COLLECT
      do {
        if (!self.nowStreaming) {
          let collectCall = try service.collect() {call in
            print("Started collect \(call)")
          }
          self.collectCall = collectCall
          self.nowStreaming = true
          DispatchQueue.main.async {
            self.closeButton.isEnabled = true
          }
        }
        try self.sendCollectMessage()
      } catch (let error) {
        self.displayMessageReceived("No message received. \(error)")
      }
    }
    else if (self.callSelectButton.selectedSegment == 3) {
      // STREAMING UPDATE
      do {
        if (!self.nowStreaming) {
          let updateCall = try service.update() {call in
            print("Started update \(call)")
          }
          self.updateCall = updateCall
          self.nowStreaming = true
          try self.receiveUpdateMessages()
          DispatchQueue.main.async {
            self.closeButton.isEnabled = true
          }
        }
        try self.sendUpdateMessage()
      } catch (let error) {
        self.displayMessageReceived("No message received. \(error)")
      }
    }
  }

  func receiveExpandMessages() throws -> Void {
    guard let expandCall = expandCall else {
      return
    }
    try expandCall.receive() {response, error in
      if let responseMessage = response {
        self.displayMessageReceived(responseMessage.text)
        try! self.receiveExpandMessages()
      } else if let error = error {
        switch error {
        case .endOfStream:
          self.displayMessageReceived("Done.")
        default:
          self.displayMessageReceived("No message received. \(error)")
        }
      }
    }
  }

  func sendCollectMessage() throws {
    if let collectCall = collectCall {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = self.messageField.stringValue
      self.displayMessageSent(requestMessage.text)
      try collectCall.send(requestMessage) {error in print(error)}
    }
  }

  func sendUpdateMessage() throws {
    if let updateCall = updateCall {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = self.messageField.stringValue
      self.displayMessageSent(requestMessage.text)
      try updateCall.send(requestMessage) {error in print(error)}
    }
  }

  func receiveUpdateMessages() throws -> Void {
    guard let updateCall = updateCall else {
      return
    }
    try updateCall.receive() {response, error in
      if let responseMessage = response {
        self.displayMessageReceived(responseMessage.text)
        try! self.receiveUpdateMessages()
      } else if let error = error {
        switch error {
        case .endOfStream:
          self.displayMessageReceived("Done.")
        default:
          self.displayMessageReceived("No message received. \(error)")
        }
      }
    }
  }

  func sendClose() throws {
    if let updateCall = updateCall {
      try updateCall.closeSend() {
        self.updateCall = nil
        self.nowStreaming = false
        DispatchQueue.main.async {
          self.closeButton.isEnabled = false
        }
      }
    }
    if let collectCall = collectCall {
      do {
        try collectCall.closeAndReceive() {response, error in
          if let response = response {
            self.displayMessageReceived(response.text)
          } else if let error = error {
            self.displayMessageReceived("No message received. \(error)")
          }
          self.collectCall = nil
          self.nowStreaming = false
          DispatchQueue.main.async {
            self.closeButton.isEnabled = false
          }
        }
      }
    }
  }
}
