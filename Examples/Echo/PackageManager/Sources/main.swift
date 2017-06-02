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
