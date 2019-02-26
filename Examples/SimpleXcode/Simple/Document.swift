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
import Cocoa
import SwiftGRPC

// https://gist.github.com/rickw/cc198001f5f3aa59ae9f
extension NSTextView {
  func appendText(line: String) {
    if let textStorage = self.textStorage {
      textStorage.append(NSAttributedString(string: line + "\n",
                                            attributes: [NSFontAttributeName: NSFont.systemFont(ofSize: 12.0)]))
    }
    if let contents = self.string {
      scrollRangeToVisible(NSRange(location: contents.lengthOfBytes(using: String.Encoding.utf8), length: 0))
    }
  }
}

// http://stackoverflow.com/a/28976644/35844
func sync(lock: AnyObject, closure: () -> Void) {
  objc_sync_enter(lock)
  closure()
  objc_sync_exit(lock)
}

class Document: NSDocument {
  @IBOutlet var hostField: NSTextField!
  @IBOutlet var portField: NSTextField!
  @IBOutlet var connectionSelector: NSSegmentedControl!
  @IBOutlet var startButton: NSButton!
  @IBOutlet var textView: NSTextView!
  // http://stackoverflow.com/questions/24062437/cannot-form-weak-reference-to-instance-of-class-nstextview

  var channel: Channel!
  var server: Server!
  var running: Bool // all accesses to this should be synchronized

  override init() {
    running = false
    super.init()
  }

  override func close() {
    textView = nil // prevents logging to the textView
    stop()
    super.close()
  }

  override var windowNibName: String? {
    return "Document"
  }

  func log(_ line: String) {
    DispatchQueue.main.async {
      if let view = self.textView {
        view.appendText(line: line)
      }
    }
  }

  @IBAction func startButtonPressed(sender: NSButton) {
    if sender.title == "Start" {
      updateInterfaceBeforeStarting()
      let address = hostField.stringValue + ":" + portField.stringValue
      if connectionSelector.selectedSegment == 0 {
        runClient(address: address)
      } else {
        runServer(address: address)
      }
    } else {
      stop()
    }
  }

  func updateInterfaceBeforeStarting() {
    startButton.title = "Stop"
    hostField.isEnabled = false
    portField.isEnabled = false
    connectionSelector.isEnabled = false
    if let textStorage = self.textView.textStorage {
      textStorage.setAttributedString(NSAttributedString(string: "", attributes: [:]))
    }
  }

  func updateInterfaceAfterStopping() {
    DispatchQueue.main.async {
      if self.startButton != nil {
        self.startButton.title = "Start"
        self.hostField.isEnabled = true
        self.portField.isEnabled = true
        self.connectionSelector.isEnabled = true
      }
    }
  }

  func setIsRunning(_ value: Bool) {
    sync(lock: self) {
      self.running = value
    }
  }

  func isRunning() -> Bool {
    var result: Bool = false
    sync(lock: self) {
      result = self.running
    }
    return result
  }

  func stop() {
    if channel != nil {
      setIsRunning(false) // stops client
    }
    if server != nil {
      server.stop() // stops server
    }
  }

  func runClient(address: String) {
    DispatchQueue.global().async {
      self.log("Client Starting")
      self.log("GRPC version " + gRPC.version)

      self.channel = Channel(address: address, secure: false)
      self.channel.host = "foo.test.google.fr"
      let messageData = "hello, server!".data(using: .utf8)

      let steps = 10
      self.setIsRunning(true)
      for i in 1...steps {
        if !self.isRunning() {
          break
        }

        do {
          let method = (i < steps) ? "/hello" : "/quit"
          let call = try self.channel.makeCall(method)

          let metadata = try Metadata([
            "x": "xylophone",
            "y": "yu",
            "z": "zither"
          ])

          try call.start(.unary,
                         metadata: metadata,
                         message: messageData) { callResult in

            if let initialMetadata = callResult.initialMetadata {
              for j in 0..<initialMetadata.count() {
                self.log("\(i): Received initial metadata -> " + initialMetadata.key(j)!
                  + " : " + initialMetadata.value(j)!)
              }
            }

            self.log("\(i): Received status: \(callResult.statusCode) \(callResult.statusMessage ?? "(nil)")")
            if callResult.statusCode != .ok {
              self.setIsRunning(false)
            }
            if let messageData = callResult.resultData {
              let messageString = String(data: messageData as Data, encoding: .utf8)
              self.log("\(i): Received message: " + messageString!)
            }

            if let trailingMetadata = callResult.trailingMetadata {
              for j in 0..<trailingMetadata.count() {
                self.log("\(i): Received trailing metadata -> " + trailingMetadata.key(j)!
                  + " : " + trailingMetadata.value(j)!)
              }
            }
          }
        } catch {
          Swift.print("call error \(error)")
        }
        self.log("------------------------------")
        sleep(1)
      }
      self.log("Client Stopped")
      self.updateInterfaceAfterStopping()
    }
  }

  func runServer(address: String) {
    log("Server Starting")
    log("GRPC version " + gRPC.version)
    setIsRunning(true)

    server = Server(address: address)
    var requestCount = 0

    server.run { requestHandler in

      do {
        requestCount += 1

        self.log("\(requestCount): Received request \(requestHandler.host ?? "(nil)") \(requestHandler.method ?? "(nil)") from \(requestHandler.caller ?? "(nil)")")

        let initialMetadata = requestHandler.requestMetadata
        for i in 0..<initialMetadata.count() {
          self.log("\(requestCount): Received initial metadata -> " + initialMetadata.key(i)!
            + ":" + initialMetadata.value(i)!)
        }

        let initialMetadataToSend = try! Metadata([
          "a": "Apple",
          "b": "Banana",
          "c": "Cherry"
        ])
        try requestHandler.receiveMessage(initialMetadata: initialMetadataToSend) { messageData in
          let messageString = String(data: messageData!, encoding: .utf8)
          self.log("\(requestCount): Received message: " + messageString!)
        }

        if requestHandler.method == "/quit" {
          self.stop()
        }

        let replyMessage = "hello, client!"
        let trailingMetadataToSend = try! Metadata([
          "0": "zero",
          "1": "one",
          "2": "two"
        ])
        try requestHandler.sendResponse(message: replyMessage.data(using: .utf8)!,
										status: ServerStatus(code: .ok, message: "OK", trailingMetadata: trailingMetadataToSend))

        self.log("------------------------------")
      } catch {
        Swift.print("call error \(error)")
      }
    }

    server.onCompletion = {
      self.log("Server Stopped")
      self.updateInterfaceAfterStopping()
    }
  }
}
