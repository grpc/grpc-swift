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

// The following code is for developer/users to edit.
// Everything above these lines is intended to be preexisting or generated.

class MyEchoServer : CustomEchoServer {

  func Get(request : Echo_EchoRequest) throws -> Echo_EchoResponse {
    return Echo_EchoResponse(text:"Swift echo get: " + request.text)
  }

  func Expand(request : Echo_EchoRequest, session : EchoExpandSession) throws -> Void {
    let parts = request.text.components(separatedBy: " ")
    var i = 0
    for part in parts {
      try! session.Send(Echo_EchoResponse(text:"Swift echo expand (\(i)): \(part)"))
      i += 1
      sleep(1)
    }
  }

  func Collect(session : EchoCollectSession) throws -> Void {
    DispatchQueue.global().async {
      var parts : [String] = []
      while true {
        do {
          let request = try session.Recv()
          parts.append(request.text)
        } catch ServerError.endOfStream {
          break
        } catch (let error) {
          print("\(error)")
        }
      }
      let response = Echo_EchoResponse(text:"Swift echo collect: " + parts.joined(separator: " "))
      try! session.SendAndClose(response)
    }
  }

  func Update(session : EchoUpdateSession) throws -> Void {
    DispatchQueue.global().async {
      var count = 0
      while true {
        do {
          let request = try session.Recv()
          count += 1
          try session.Send(Echo_EchoResponse(text:"Swift echo update (\(count)): \(request.text)"))
        } catch ServerError.endOfStream {
          break
        } catch (let error) {
          print("\(error)")
        }
      }
      session.Close()
    }
  }
}
