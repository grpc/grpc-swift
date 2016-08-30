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
import CgRPC
import gRPC
import QuickProto

let address = "localhost:8080"

gRPC.initialize()

if let fileDescriptorSetProto = NSData(contentsOfFile:"echo.out") {
  let fileDescriptorSet = FileDescriptorSet(proto:fileDescriptorSetProto)
  if let requestMessage = fileDescriptorSet.createMessage(name:"EchoRequest") {
    requestMessage.addField(name:"text", value:"hello, swifty!")

    let requestHost = "foo.test.google.fr"
    let requestMethod = "/echo.Echo/Get"
    let requestBuffer = ByteBuffer(data:requestMessage.serialize())
    let requestMetadata = Metadata()

    let client = Client(address:address)
    let response = client.performRequest(host:requestHost,
                                         method:requestMethod,
                                         message:requestBuffer,
                                         metadata:requestMetadata)

    print("Received status: \(response.status) " + response.statusDetails)

    if let responseBuffer = response.message,
      let responseMessage = fileDescriptorSet.readMessage(name:"EchoResponse",
                                                          proto:responseBuffer.data()) {
      responseMessage.forOneField(name:"text") {(field) in
        print(field.string())
      }
    } else {
      print("No message received. gRPC Status \(response.status) " + response.statusDetails)
    }
  }
}
