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

let address = "localhost:8001"
let host = "foo.test.google.fr"
let message = gRPC.ByteBuffer(string:"hello gRPC server!")

gRPC.initialize()
print("gRPC version", gRPC.version())

do {
  let c = gRPC.Client(address:address)
  let steps = 30
  for i in 0..<steps {
    let method = (i < steps-1) ? "/hello" : "/quit"

    let metadata = Metadata(pairs:[MetadataPair(key:"x", value:"xylophone"),
                                   MetadataPair(key:"y", value:"yu"),
                                   MetadataPair(key:"z", value:"zither")])

    let response = c.performRequest(host:host,
                                    method:method,
                                    message:message,
                                    metadata:metadata)
    print("status:", response.status)
    print("statusDetails:", response.statusDetails)
    if let message = response.message {
      print("message:", message.string())
    }

    let initialMetadata = response.initialMetadata!
    for i in 0..<initialMetadata.count() {
      print("INITIAL METADATA ->", initialMetadata.key(index:i), ":", initialMetadata.value(index:i))
    }

    let trailingMetadata = response.trailingMetadata!
    for i in 0..<trailingMetadata.count() {
      print("TRAILING METADATA ->", trailingMetadata.key(index:i), ":", trailingMetadata.value(index:i))
    }

    if (response.status != 0) {
      break
    }
  }
}
gRPC.shutdown()
print("Done")
