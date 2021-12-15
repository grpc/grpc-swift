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
import NIOCore

internal final class MetadataEchoProvider: Echo_EchoProvider {
  let interceptors: Echo_EchoServerInterceptorFactoryProtocol? = nil

  func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    let response = Echo_EchoResponse.with {
      $0.text = context.headers.sorted(by: { $0.name < $1.name }).map {
        $0.name + ": " + $0.value
      }.joined(separator: "\n")
    }

    return context.eventLoop.makeSucceededFuture(response)
  }

  func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    return context.eventLoop.makeFailedFuture(GRPCStatus(code: .unimplemented))
  }

  func collect(
    context: UnaryResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeFailedFuture(GRPCStatus(code: .unimplemented))
  }

  func update(
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    return context.eventLoop.makeFailedFuture(GRPCStatus(code: .unimplemented))
  }
}
