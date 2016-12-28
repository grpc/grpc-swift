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

let address = "localhost:8001"

gRPC.initialize()

guard let fileDescriptorSetProto = NSData(contentsOfFile:"echo.out")
  else {
    print("Missing echo.out")
    exit(-1)
}

let fileDescriptorSet = FileDescriptorSet(data:Data(bytes:fileDescriptorSetProto.bytes,
                                                          count:fileDescriptorSetProto.length))

let requestMethod = "/echo.Echo/Get"

if let requestMessage = fileDescriptorSet.makeMessage("EchoRequest") {
  requestMessage.addField("text", value:"hello, swifty!")
  let requestMessageData = requestMessage.data()
  let requestMetadata = Metadata()

  let channel = Channel(address:address)
  let call = channel.makeCall(requestMethod)

  let done = NSCondition()
  do {
    print("Calling echo service")
    try call.perform(message:requestMessageData,
                     metadata:requestMetadata)
    {(response) in
      print("Received status: \(response.statusCode) " + response.statusMessage!)
      // unpack and process message
      if let responseData = response.resultData,
        let responseMessage = fileDescriptorSet.readMessage("EchoResponse", data:responseData) {
        try responseMessage.forOneField("text") {(field) in
          print(field.string())
        }
      } else {
        print("No message received. gRPC Status \(response.statusCode) " + response.statusMessage!)
      }
      done.lock()
      done.signal()
      done.unlock()
    }
  } catch let error {
    print("\(error)")
    done.lock()
    done.signal()
    done.unlock()
  }
  done.lock()
  done.wait()
  done.unlock()
}
