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
import EchoModel
import Foundation
import GRPC
import NIO
import SwiftProtobuf

public class EchoProvider: Echo_EchoProvider {
  public let interceptors: Echo_EchoServerInterceptorFactoryProtocol?

  public init(interceptors: Echo_EchoServerInterceptorFactoryProtocol? = nil) {
    self.interceptors = interceptors
  }

  public func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    let response = Echo_EchoResponse.with {
      $0.text = "Swift echo get: " + request.text
    }
    return context.eventLoop.makeSucceededFuture(response)
  }

  public func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    let responses = request.text.components(separatedBy: " ").lazy.enumerated().map { i, part in
      Echo_EchoResponse.with {
        $0.text = "Swift echo expand (\(i)): \(part)"
      }
    }

    context.sendResponses(responses, promise: nil)
    return context.eventLoop.makeSucceededFuture(.ok)
  }

  public func collect(
    context: UnaryResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    var parts: [String] = []
    return context.eventLoop.makeSucceededFuture({ event in
      switch event {
      case let .message(message):
        parts.append(message.text)

      case .end:
        let response = Echo_EchoResponse.with {
          $0.text = "Swift echo collect: " + parts.joined(separator: " ")
        }
        context.responsePromise.succeed(response)
      }
    })
  }

  public func update(
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    var count = 0
    return context.eventLoop.makeSucceededFuture({ event in
      switch event {
      case let .message(message):
        let response = Echo_EchoResponse.with {
          $0.text = "Swift echo update (\(count)): \(message.text)"
        }
        count += 1
        context.sendResponse(response, promise: nil)

      case .end:
        context.statusPromise.succeed(.ok)
      }
    })
  }
}
