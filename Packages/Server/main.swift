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

gRPC.initialize()
print("gRPC version", gRPC.version())
do {
  let server = gRPC.Server(address:"localhost:8001")
  server.start()
  var running = true
  while(running) {
    let (_, status, requestHandler) = server.getNextRequest(timeout:600)
    if let requestHandler = requestHandler {
      print("HOST:", requestHandler.host())
      print("METHOD:", requestHandler.method())
      let initialMetadata = requestHandler.requestMetadata
      for i in 0..<initialMetadata.count() {
        print("INITIAL METADATA ->", initialMetadata.key(index:i), ":", initialMetadata.value(index:i))
      }
  
      let initialMetadataToSend = Metadata()
      initialMetadataToSend.add(key:"a", value:"Apple")
      initialMetadataToSend.add(key:"b", value:"Banana")
      initialMetadataToSend.add(key:"c", value:"Cherry")
      let (_, _, message) = requestHandler.receiveMessage(initialMetadata:initialMetadataToSend)
      print("MESSAGE", message!.string())
      if requestHandler.method() == "/quit" {
        running = false
      }
      let trailingMetadataToSend = Metadata()
      trailingMetadataToSend.add(key:"0", value:"zero")
      trailingMetadataToSend.add(key:"1", value:"one")
      trailingMetadataToSend.add(key:"2", value:"two")
      let (_, _) = requestHandler.sendResponse(message:ByteBuffer(string:"thank you very much!"),
                                               trailingMetadata:trailingMetadataToSend)
    }
  }
}
gRPC.shutdown()
print("DONE")
