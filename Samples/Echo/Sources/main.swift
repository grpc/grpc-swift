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
var client_get : Bool = false
var client_expand : Bool = false
var client_collect : Bool = false
var client_update : Bool = false

// other network configuration
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
  } else if arg == "get" {
    client_get = true
  } else if arg == "expand" {
    client_expand = true
  } else if arg == "collect" {
    client_collect = true
  } else if arg == "update" {
    client_update = true
  } else if arg == "-ssl" {
    useSSL = true
  }
}

var insecureEchoServer: EchoServer!
var secureEchoServer: EchoServer!

var done = NSCondition()

gRPC.initialize()

if server {
  if useSSL {
    print("Starting secure server")
    secureEchoServer = EchoServer(address:"localhost:8443", secure:true)
    secureEchoServer.start()
  } else {
    print("Starting insecure server")
    insecureEchoServer = EchoServer(address:"localhost:8081", secure:false)
    insecureEchoServer.start()
  }
  // we never actually exit the server; kill the process to stop it.
  done.lock()
  done.wait()
  done.unlock()
}

if client_get || client_expand || client_collect || client_update {
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

  if client_get {
    let getCall = service.get()

    var requestMessage = Echo_EchoRequest()
    requestMessage.text = "Hello!!!"
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
    done.lock()
    done.wait()
    done.unlock()
  }

  if client_expand {
    let expandCall = service.expand()

    func receiveExpandMessage() throws -> Void {
      try expandCall.receiveMessage() {(responseMessage) in
        if let responseMessage = responseMessage {
          try receiveExpandMessage() // prepare to receive the next message
          print(responseMessage.text)
        } else {
          print("expand closed")
          done.lock()
          done.signal()
          done.unlock()
        }
      }
    }

    var requestMessage = Echo_EchoRequest()
    requestMessage.text = "Testing One Two Three"
    print("Sending: " + requestMessage.text)
    expandCall.perform(request:requestMessage) {(callResult, response) in}
    try receiveExpandMessage()
    done.lock()
    done.wait()
    done.unlock()
  }

  if client_collect {
    let collectCall = service.collect()

    func sendCollectMessage() {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = "hello"
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
        } else {
          print("collect closed")
          done.lock()
          done.signal()
          done.unlock()
        }
      }
    }
    try collectCall.start(metadata:requestMetadata)
    try receiveCollectMessage()
    sendCollectMessage()
    sleep(1)
    sendCollectMessage()
    sleep(1)
    sendCollectMessage()
    sleep(1)
    sendClose()

    done.lock()
    done.wait()
    done.unlock()
  }

  if client_update {
    let updateCall = service.update()

    func sendUpdateMessage() {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = "hello"
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
        } else {
          print("update closed")
          done.lock()
          done.signal()
          done.unlock()
        }
      }
    }

    try updateCall.start(metadata:requestMetadata)
    try receiveUpdateMessage()
    sendUpdateMessage()
    sleep(1)
    sendUpdateMessage()
    sleep(1)
    sendUpdateMessage()
    sleep(1)
    sendClose()
    sleep(1)
    done.lock()
    done.wait()
    done.unlock()
  }
}



