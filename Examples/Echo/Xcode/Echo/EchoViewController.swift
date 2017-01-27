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
      service = Echo_EchoService(address:address)
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
      let requestMessage = Echo_EchoRequest(text:self.messageField.stringValue)
      self.displayMessageSent(requestMessage.text)
      // run this asynchronously because service.get() is a blocking call
      DispatchQueue.global().async {
        do {
          let responseMessage = try service.get(requestMessage)
          self.displayMessageReceived(responseMessage.text)
        } catch (let error) {
          self.displayMessageReceived("No message received. \(error)")
        }
      }
    }
    else if (self.callSelectButton.selectedSegment == 1) {
      // STREAMING EXPAND
      if (!nowStreaming) {
        DispatchQueue.global().async {
          do {
            let requestMessage = Echo_EchoRequest(text:self.messageField.stringValue)
            self.expandCall = try service.expand(requestMessage)
            self.displayMessageSent(requestMessage.text)
            try self.receiveExpandMessages()
          } catch (let error) {
            self.displayMessageReceived("No message received. \(error)")
          }
        }
      }
    }
    else if (self.callSelectButton.selectedSegment == 2) {
      // STREAMING COLLECT
      DispatchQueue.global().async {
        do {
          if (!self.nowStreaming) {
            self.collectCall = try service.collect()
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
    }
    else if (self.callSelectButton.selectedSegment == 3) {
      // STREAMING UPDATE
      DispatchQueue.global().async {
        do {
          if (!self.nowStreaming) {
            self.updateCall = try service.update()
            try self.receiveUpdateMessages()
            self.nowStreaming = true
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
  }

  func receiveExpandMessages() throws -> Void {
    guard let expandCall = expandCall else {
      return
    }
    DispatchQueue.global().async {
      var running = true
      while running {
        do {
          let responseMessage = try expandCall.receive()
          self.displayMessageReceived(responseMessage.text)
        } catch Echo_EchoClientError.endOfStream {
          self.displayMessageReceived("Done.")
          running = false
        } catch (let error) {
          self.displayMessageReceived("No message received. \(error)")
        }
      }
    }
  }

  func sendCollectMessage() throws {
    if let collectCall = collectCall {
      let requestMessage = Echo_EchoRequest(text:self.messageField.stringValue)
      self.displayMessageSent(requestMessage.text)
      try collectCall.send(requestMessage)
    }
  }

  func sendUpdateMessage() throws {
    if let updateCall = updateCall {
      let requestMessage = Echo_EchoRequest(text:self.messageField.stringValue)
      self.displayMessageSent(requestMessage.text)
      try updateCall.send(requestMessage)
    }
  }

  func receiveUpdateMessages() throws -> Void {
    guard let updateCall = updateCall else {
      return
    }
    DispatchQueue.global().async {
      var running = true
      while running {
        do {
          let responseMessage = try updateCall.receive()
          self.displayMessageReceived(responseMessage.text)
        } catch Echo_EchoClientError.endOfStream {
          self.displayMessageReceived("Done.")
          running = false
        } catch (let error) {
          self.displayMessageReceived("No message received. \(error)")
        }
      }
    }
  }

  func sendClose() throws {
    if let updateCall = updateCall {
      try updateCall.closeSend()
      self.updateCall = nil
      self.nowStreaming = false
      self.closeButton.isEnabled = false
    }
    if let collectCall = collectCall {
      do {
        let responseMessage = try collectCall.closeAndReceive()
        self.displayMessageReceived(responseMessage.text)
      } catch (let error) {
        self.displayMessageReceived("No message received. \(error)")
      }
      self.collectCall = nil
      self.nowStreaming = false
      self.closeButton.isEnabled = false
    }
  }
}
