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
import CgRPC
import Dispatch

print("\(CommandLine.arguments)")

// server options
var server : Bool = false

// client options
var client : String = ""
var message : String = "Testing 1 2 3"

// self-test mode
var test : Bool = false

// general configuration
var useSSL : Bool = false

var i : Int = 0
while i < Int(CommandLine.argc) {
  let arg = CommandLine.arguments[i]
  i = i + 1
  if i == 1 {
    continue // skip the first argument
  }

  if arg == "test" {
    test = true
  } else if arg == "serve" {
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

var latch = CountDownLatch(1)

gRPC.initialize()

if server {
  let echoProvider = EchoProvider()
  var echoServer: Echo_EchoServer!

  if useSSL {
    print("Starting secure server")
    let certificateURL = URL(fileURLWithPath:"ssl.crt")
    let keyURL = URL(fileURLWithPath:"ssl.key")
    echoServer = Echo_EchoServer(address:"localhost:8443",
                                 certificateURL:certificateURL,
                                 keyURL:keyURL,
                                 provider:echoProvider)
  } else {
    print("Starting insecure server")
    echoServer = Echo_EchoServer(address:"localhost:8081",
                                 provider:echoProvider)
  }
  echoServer.start()
  // Block to keep the main thread from finishing while the server runs.
  // This server never exits. Kill the process to stop it.
  latch.wait()
}

if client != "" {
  print("Starting client")

  var service : Echo_EchoService
  if useSSL {
    let certificateURL = URL(fileURLWithPath:"ssl.crt")
    let certificates = try! String(contentsOf: certificateURL)
    service = Echo_EchoService(address:"localhost:8443", certificates:certificates, host:"example.com")
    service.host = "example.com" // sample override
  } else {
    service = Echo_EchoService(address:"localhost:8081")
  }

  let requestMetadata = Metadata(["x-goog-api-key":"YOUR_API_KEY",
                                  "x-ios-bundle-identifier":"com.google.echo"])

  // Unary
  if client == "get" {
    var requestMessage = Echo_EchoRequest()
    requestMessage.text = message
    print("Sending: " + requestMessage.text)
    let responseMessage = try service.get(requestMessage)
    print("get received: " + responseMessage.text)
  }

  // Server streaming
  if client == "expand" {
    var requestMessage = Echo_EchoRequest()
    requestMessage.text = message
    print("Sending: " + requestMessage.text)
    let expandCall = try service.expand(requestMessage) {result in }
    var running = true
    while running {
      do {
        let responseMessage = try expandCall.receive()
        print("Received: \(responseMessage.text)")
      } catch Echo_EchoClientError.endOfStream {
        print("expand closed")
        running = false
      }
    }
  }

  // Client streaming
  if client == "collect" {
    let collectCall = try service.collect() {result in }

    let parts = message.components(separatedBy:" ")
    for part in parts {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = part
      print("Sending: " + part)
      try collectCall.send(requestMessage) {error in print(error)}
      sleep(1)
    }

    let responseMessage = try collectCall.closeAndReceive()
    print("Received: \(responseMessage.text)")
  }

  // Bidirectional streaming
  if client == "update" {
    let updateCall = try service.update() {result in}

    DispatchQueue.global().async {
      var running = true
      while running {
        do {
          let responseMessage = try updateCall.receive()
          print("Received: \(responseMessage.text)")
        } catch Echo_EchoClientError.endOfStream {
          print("update closed")
          latch.signal()
          break
        } catch (let error) {
          print("error: \(error)")
        }
      }
    }

    let parts = message.components(separatedBy:" ")
    for part in parts {
      var requestMessage = Echo_EchoRequest()
      requestMessage.text = part
      print("Sending: " + requestMessage.text)
      try updateCall.send(requestMessage) {error in print(error)}
      sleep(1)
    }
    try updateCall.closeSend()

    // Wait for the call to complete.
    latch.wait()
  }
}

if test {
  print("self test")
}
