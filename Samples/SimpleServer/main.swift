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
import gRPC
import Foundation

gRPC.initialize()
print("gRPC version", gRPC.version())

let server = gRPC.Server(address:"localhost:8001")
var requestCount = 0

let done = NSCondition()

server.run() {(requestHandler) in

  do {
    requestCount += 1

    print("\(requestCount): Received request " + requestHandler.host
      + " " + requestHandler.method
      + " from " + requestHandler.caller)

    let initialMetadata = requestHandler.requestMetadata
    for i in 0..<initialMetadata.count() {
      print("\(requestCount): Received initial metadata -> " + initialMetadata.key(index:i)
        + ":" + initialMetadata.value(index:i))
    }

    let initialMetadataToSend = Metadata([["a": "Apple"],
                                          ["b": "Banana"],
                                          ["c": "Cherry"]])
    try requestHandler.receiveMessage(initialMetadata:initialMetadataToSend)
    {(messageData) in
      let messageString = String(data: messageData!, encoding: .utf8)
      print("\(requestCount): Received message: " + messageString!)
    }

    if requestHandler.method == "/quit" {
      print("quitting")
      done.lock()
      done.signal()
      done.unlock()
    }

    let replyMessage = "hello, client!"
    let trailingMetadataToSend = Metadata([["0": "zero"],
                                           ["1": "one"],
                                           ["2": "two"]])
    try requestHandler.sendResponse(message:replyMessage.data(using: .utf8)!,
                                    statusCode:0,
                                    statusMessage:"OK",
                                    trailingMetadata:trailingMetadataToSend)

    print("------------------------------")
  } catch (let callError) {
    Swift.print("call error \(callError)")
  }
}

server.onCompletion() {
  print("Server Stopped")
}

done.lock()
done.wait()
done.unlock()

