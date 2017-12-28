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
import Dispatch

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
      let sem = DispatchSemaphore(value: 0)
      try session.send(response) {sem.signal()}
      _ = sem.wait(timeout: DispatchTime.distantFuture)
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
        let sem = DispatchSemaphore(value: 0)
        try session.send(response) {sem.signal()}
        _ = sem.wait(timeout: DispatchTime.distantFuture)
      } catch Echo_EchoServerError.endOfStream {
        break
      } catch (let error) {
        print("\(error)")
      }
    }
    try session.close()
  }
}
