/*
 * Copyright 2018, gRPC Authors All rights reserved.
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
import NIO
import GRPC
import EchoModel

public class EchoProvider: Echo_EchoProvider {
  public init() {}

  public func get(request: Echo_EchoRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Echo_EchoResponse> {
    var response = Echo_EchoResponse()
    response.text = "Swift echo get: " + request.text
    return context.eventLoop.makeSucceededFuture(response)
  }

  public func expand(request: Echo_EchoRequest, context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<GRPCStatus> {
    var endOfSendOperationQueue = context.eventLoop.makeSucceededFuture(())
    let parts = request.text.components(separatedBy: " ")
    for (i, part) in parts.enumerated() {
      var response = Echo_EchoResponse()
      response.text = "Swift echo expand (\(i)): \(part)"
      endOfSendOperationQueue = endOfSendOperationQueue.flatMap { context.sendResponse(response) }
    }
    return endOfSendOperationQueue.map { GRPCStatus.ok }
  }

  public func collect(context: UnaryResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    var parts: [String] = []
    return context.eventLoop.makeSucceededFuture({ event in
      switch event {
      case .message(let message):
        parts.append(message.text)

      case .end:
        var response = Echo_EchoResponse()
        response.text = "Swift echo collect: " + parts.joined(separator: " ")
        context.responsePromise.succeed(response)
      }
    })
  }

  public func update(context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    var endOfSendOperationQueue = context.eventLoop.makeSucceededFuture(())
    var count = 0
    return context.eventLoop.makeSucceededFuture({ event in
      switch event {
      case .message(let message):
        var response = Echo_EchoResponse()
        response.text = "Swift echo update (\(count)): \(message.text)"
        endOfSendOperationQueue = endOfSendOperationQueue.flatMap { context.sendResponse(response) }
        count += 1

      case .end:
        endOfSendOperationQueue
          .map { GRPCStatus.ok }
          .cascade(to: context.statusPromise)
      }
    })
  }
}
