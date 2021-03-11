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

/// An `Echo_EchoProvider` which sets `onClose` for each RPC and then calls a delegate to provide
/// the RPC implementation.
class OnCloseEchoProvider: Echo_EchoProvider {
  let interceptors: Echo_EchoServerInterceptorFactoryProtocol?

  let onClose: (Result<Void, Error>) -> Void
  let delegate: Echo_EchoProvider

  init(
    delegate: Echo_EchoProvider,
    interceptors: Echo_EchoServerInterceptorFactoryProtocol? = nil,
    onClose: @escaping (Result<Void, Error>) -> Void
  ) {
    self.delegate = delegate
    self.onClose = onClose
    self.interceptors = interceptors
  }

  func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    context.closeFuture.whenComplete(self.onClose)
    return self.delegate.get(request: request, context: context)
  }

  func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    context.closeFuture.whenComplete(self.onClose)
    return self.delegate.expand(request: request, context: context)
  }

  func collect(
    context: UnaryResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    context.closeFuture.whenComplete(self.onClose)
    return self.delegate.collect(context: context)
  }

  func update(
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    context.closeFuture.whenComplete(self.onClose)
    return self.delegate.update(context: context)
  }
}
