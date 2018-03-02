/*
 * Copyright 2017, gRPC Authors All rights reserved.
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
import Commander
import Dispatch
import Foundation
import gRPC

let address = "localhost:8001"
let host = "foo.test.google.fr"

func client() throws {
  let message = "hello, server!".data(using: .utf8)
  let c = Channel(address: address, secure: false)
  let steps = 3
  for i in 0..<steps {
    let sem = DispatchSemaphore(value: 0)

    let method = (i < steps - 1) ? "/hello" : "/quit"
    print("calling " + method)
    let call = c.makeCall(method)

    let metadata = Metadata([
      "x": "xylophone",
      "y": "yu",
      "z": "zither"
    ])

    try! call.start(.unary, metadata: metadata, message: message) {
      response in
      print("status:", response.statusCode)
      print("statusMessage:", response.statusMessage!)
      if let resultData = response.resultData {
        print("message: \(resultData)")
      }

      let initialMetadata = response.initialMetadata!
      for i in 0..<initialMetadata.count() {
        print("INITIAL METADATA ->", initialMetadata.key(i)!, ":", initialMetadata.value(i)!)
      }

      let trailingMetadata = response.trailingMetadata!
      for i in 0..<trailingMetadata.count() {
        print("TRAILING METADATA ->", trailingMetadata.key(i)!, ":", trailingMetadata.value(i)!)
      }
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
  }
  print("Done")
}

func server() throws {
  let server = Server(address: address)
  var requestCount = 0

  let sem = DispatchSemaphore(value: 0)

  server.run { requestHandler in

    do {
      requestCount += 1

      print("\(requestCount): Received request " + requestHandler.host!
          + " " + String(describing:requestHandler.method) 
          + " from " + String(describing:requestHandler.caller))

      let initialMetadata = requestHandler.requestMetadata
      for i in 0..<initialMetadata.count() {
        print("\(requestCount): Received initial metadata -> " + initialMetadata.key(i)!
          + ":" + initialMetadata.value(i)!)
      }

      let initialMetadataToSend = Metadata([
        "a": "Apple",
        "b": "Banana",
        "c": "Cherry"
      ])
      try requestHandler.receiveMessage(initialMetadata: initialMetadataToSend) { messageData in
        let messageString = String(data: messageData!, encoding: .utf8)
        print("\(requestCount): Received message: " + messageString!)
      }

      if requestHandler.method == "/quit" {
        print("quitting")
        sem.signal()
      }

      let replyMessage = "hello, client!"
      let trailingMetadataToSend = Metadata([
        "0": "zero",
        "1": "one",
        "2": "two"
      ])
      try requestHandler.sendResponse(message: replyMessage.data(using: .utf8)!,
                                      statusCode: .ok,
                                      statusMessage: "OK",
                                      trailingMetadata: trailingMetadataToSend)

      print("------------------------------")
    } catch (let callError) {
      Swift.print("call error \(callError)")
    }
  }

  server.onCompletion = {
    print("Server Stopped")
  }

  _ = sem.wait(timeout: DispatchTime.distantFuture)
}

Group {
  $0.command("server") {
    gRPC.initialize()
    print("gRPC version", gRPC.version)
    try server()
  }

  $0.command("client") {
    gRPC.initialize()
    print("gRPC version", gRPC.version)
    try client()
  }

}.run()
