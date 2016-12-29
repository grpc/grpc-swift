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
import Foundation
import gRPC
import QuickProto

print("\(CommandLine.arguments)")

// server options
var server : Bool = false

// client options
var client : String = ""
var message : String = "Testing 1 2 3"

// general configuration
var useSSL : Bool = false

var i : Int = 0
while i < Int(CommandLine.argc) {
  let arg = CommandLine.arguments[i]
  i = i + 1
  if i == 1 {
    continue // skip the first argument
  }

  if arg == "serve" {
    server = true
  } else if (arg == "get") || (arg == "expand") || (arg == "collect") || (arg == "update") {
    client = arg
  } else if arg == "-ssl" {
    useSSL = true
  } else if arg == "-m" && (i < Int(CommandLine.argc)) {
    message = CommandLine.arguments[i]
    i = i + 1
  }
}

var done = NSCondition()

gRPC.initialize()

if server {
  var echoServer: EchoServer!
  if useSSL {
    print("Starting secure server")
    echoServer = EchoServer(address:"localhost:8443", secure:true)
  } else {
    print("Starting insecure server")
    echoServer = EchoServer(address:"localhost:8081", secure:false)
  }
  echoServer.start()
  // Block to keep the main thread from finishing while the server runs.
  // This server never exits. Kill the process to stop it.
  done.lock()
  done.wait()
  done.unlock()
}

if client != "" {
  print("Starting client")

  var service : EchoService
  if useSSL {
    let certificateURL = URL(fileURLWithPath:"ssl.crt")
    let certificates = try! String(contentsOf: certificateURL)
    service = EchoService(address:"localhost:8443", certificates:certificates, host:"example.com")
    service.channel.host = "example.com" // sample override
  } else {
    service = EchoService(address:"localhost:8081")
  }

  let requestMetadata = Metadata(["x-goog-api-key":"YOUR_API_KEY",
                                  "x-ios-bundle-identifier":"com.google.echo"])

  if client == "get" {
    let getCall = service.get()

    var requestMessage = Echo_EchoRequest(text:message)
    print("Sending: " + requestMessage.text)
    getCall.perform(request:requestMessage) {(callResult, responseMessage) in
      if let responseMessage = responseMessage {
        print("Received: " + responseMessage.text)
      } else {
        print("No message received. gRPC Status \(callResult.statusCode): \(callResult.statusMessage)")
      }
      done.lock()
      done.signal()
      done.unlock()
    }
    // Wait for the call to complete.
    done.lock()
    done.wait()
    done.unlock()
  }

  if client == "expand" {
    let expandCall = service.expand()

    func receiveExpandMessage() throws -> Void {
      try expandCall.receiveMessage() {(responseMessage) in
        if let responseMessage = responseMessage {
          try receiveExpandMessage() // prepare to receive the next message in the stream
          print("Received: " + responseMessage.text)
        } else {
          print("expand closed")
          done.lock()
          done.signal()
          done.unlock()
        }
      }
    }

    let requestMessage = Echo_EchoRequest(text:message)
    print("Sending: " + requestMessage.text)
    expandCall.perform(request:requestMessage) {(callResult, response) in /* do nothing */}
    try receiveExpandMessage()
    // Wait for the call to complete.
    done.lock()
    done.wait()
    done.unlock()
  }

  if client == "collect" {
    let collectCall = service.collect()

    func sendCollectMessage(message: String) {
      let requestMessage = Echo_EchoRequest(text:message)
      print("Sending: " + requestMessage.text)
      _ = collectCall.sendMessage(message:requestMessage)
    }

    func sendClose() {
      print("Closing")
      _ = try! collectCall.close(completion:{})
    }

    func receiveCollectMessage() throws -> Void {
      try collectCall.receiveMessage() {(responseMessage) in
        if let responseMessage = responseMessage {
          print("Received: " + responseMessage.text)
          done.lock()
          done.signal()
          done.unlock()
        }
      }
    }
    try collectCall.start(metadata:requestMetadata)
    try receiveCollectMessage()
    let parts = message.components(separatedBy:" ")
    for part in parts {
      sendCollectMessage(message:part)
      sleep(1)
    }
    sendClose()
    // Wait for the call to complete.
    done.lock()
    done.wait()
    done.unlock()
  }

  if client == "update" {
    let updateCall = service.update()

    func sendUpdateMessage(message: String) {
      let requestMessage = Echo_EchoRequest(text:message)
      print("Sending: " + requestMessage.text)
      _ = updateCall.sendMessage(message:requestMessage)
    }

    func sendClose() {
      print("Closing")
      _ = try! updateCall.close(completion:{})
    }

    func receiveUpdateMessage() throws -> Void {
      try updateCall.receiveMessage() {(responseMessage) in
        try receiveUpdateMessage() // prepare to receive the next message
        if let responseMessage = responseMessage {
          print("Received: " + responseMessage.text)
        }
      }
    }

    try updateCall.start(metadata:requestMetadata) {
      print("update closed")
      done.lock()
      done.signal()
      done.unlock()
    }
    try receiveUpdateMessage()
    let parts = message.components(separatedBy:" ")
    for part in parts {
      sendUpdateMessage(message:part)
      sleep(1)
    }
    sendClose()
    // Wait for the call to complete.
    done.lock()
    done.wait()
    done.unlock()
  }
}



