/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import GRPC
import NIO

/// The echo provider that comes with the example does some string processing, we'll avoid some of
/// that here so we're looking at the right things.
public class MinimalEchoProvider: Echo_EchoProvider {
  public let interceptors: Echo_EchoServerInterceptorFactoryProtocol? = nil

  public func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    return context.eventLoop.makeSucceededFuture(.with { $0.text = request.text })
  }

  public func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    for part in request.text.utf8.split(separator: UInt8(ascii: " ")) {
      context.sendResponse(.with { $0.text = String(part)! }, promise: nil)
    }
    return context.eventLoop.makeSucceededFuture(.ok)
  }

  public func collect(
    context: UnaryResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    var parts: [String] = []

    func onEvent(_ event: StreamEvent<Echo_EchoRequest>) {
      switch event {
      case let .message(request):
        parts.append(request.text)
      case .end:
        context.responsePromise.succeed(.with { $0.text = parts.joined(separator: " ") })
      }
    }

    return context.eventLoop.makeSucceededFuture(onEvent(_:))
  }

  public func update(
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    func onEvent(_ event: StreamEvent<Echo_EchoRequest>) {
      switch event {
      case let .message(request):
        context.sendResponse(.with { $0.text = request.text }, promise: nil)
      case .end:
        context.statusPromise.succeed(.ok)
      }
    }

    return context.eventLoop.makeSucceededFuture(onEvent(_:))
  }
}
