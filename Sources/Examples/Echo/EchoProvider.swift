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
import Dispatch
import Foundation
import SwiftGRPC

class EchoProvider: Echo_EchoProvider {
  // get returns requests as they were received.
  func get(request: Echo_EchoRequest, session _: Echo_EchoGetSession) throws -> Echo_EchoResponse {
    var response = Echo_EchoResponse()
    response.text = "Swift echo get: " + request.text
    return response
  }

  // expand splits a request into words and returns each word in a separate message.
  func expand(request: Echo_EchoRequest, session: Echo_EchoExpandSession) throws {
    let parts = request.text.components(separatedBy: " ")
    for (i, part) in parts.enumerated() {
      var response = Echo_EchoResponse()
      response.text = "Swift echo expand (\(i)): \(part)"
      try session.send(response) {
        if let error = $0 {
          print("expand error: \(error)")
        }
      }
    }
    session.waitForSendOperationsToFinish()
    try session.close(withStatus: .ok, completion: nil)
  }

  // collect collects a sequence of messages and returns them concatenated when the caller closes.
  func collect(session: Echo_EchoCollectSession) throws {
    var parts: [String] = []
    while true {
      do {
        guard let request = try session.receive()
          else { break }  // End of stream
        parts.append(request.text)
      } catch {
        print("collect error: \(error)")
        break
      }
    }
    var response = Echo_EchoResponse()
    response.text = "Swift echo collect: " + parts.joined(separator: " ")
    try session.sendAndClose(response: response, status: .ok, completion: nil)
  }

  // update streams back messages as they are received in an input stream.
  func update(session: Echo_EchoUpdateSession) throws {
    var count = 0
    while true {
      do {
        guard let request = try session.receive()
          else { break }  // End of stream
        var response = Echo_EchoResponse()
        response.text = "Swift echo update (\(count)): \(request.text)"
        count += 1
        try session.send(response) {
          if let error = $0 {
            print("update error: \(error)")
          }
        }
      } catch {
        print("update error: \(error)")
        break
      }
    }
    session.waitForSendOperationsToFinish()
    try session.close(withStatus: .ok, completion: nil)
  }
}
