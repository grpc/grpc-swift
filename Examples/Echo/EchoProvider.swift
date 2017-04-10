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

class EchoProvider : Echo_EchoProvider {

  // get returns requests as they were received.
  func get(request : Echo_EchoRequest, session : Echo_EchoGetSession) throws -> Echo_EchoResponse {
    var response = Echo_EchoResponse()
    response.text = "Swift echo get: " + request.text
    return response
  }

  // expand splits a request into words and returns each word in a separate message.
  func expand(request : Echo_EchoRequest, session : Echo_EchoExpandSession) throws -> Void {
    let parts = request.text.components(separatedBy: " ")
    var i = 0
    for part in parts {
      var response = Echo_EchoResponse()
      response.text = "Swift echo expand (\(i)): \(part)"
      try session.send(response)
      i += 1
      sleep(1)
    }
  }

  // collect collects a sequence of messages and returns them concatenated when the caller closes.
  func collect(session : Echo_EchoCollectSession) throws -> Void {
    var parts : [String] = []
    while true {
      do {
        let request = try session.receive()
        parts.append(request.text)
      } catch Echo_EchoServerError.endOfStream {
        break
      } catch (let error) {
        print("\(error)")
      }
    }
    var response = Echo_EchoResponse()
    response.text = "Swift echo collect: " + parts.joined(separator: " ")
    try session.sendAndClose(response)
  }

  // update streams back messages as they are received in an input stream.
  func update(session : Echo_EchoUpdateSession) throws -> Void {
    var count = 0
    while true {
      do {
        let request = try session.receive()
        count += 1
        var response = Echo_EchoResponse()
        response.text = "Swift echo update (\(count)): \(request.text)"
        try session.send(response)
      } catch Echo_EchoServerError.endOfStream {
        break
      } catch (let error) {
        print("\(error)")
      }
    }
    try session.close()
  }
}
