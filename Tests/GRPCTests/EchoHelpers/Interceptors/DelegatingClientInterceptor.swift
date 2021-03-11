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
import SwiftProtobuf

/// A client interceptor which delegates the implementation of `send` and `receive` to callbacks.
final class DelegatingClientInterceptor<
  Request: Message,
  Response: Message
>: ClientInterceptor<Request, Response> {
  typealias RequestPart = GRPCClientRequestPart<Request>
  typealias ResponsePart = GRPCClientResponsePart<Response>
  typealias Context = ClientInterceptorContext<Request, Response>
  typealias OnSend = (RequestPart, EventLoopPromise<Void>?, Context) -> Void
  typealias OnReceive = (ResponsePart, Context) -> Void

  private let onSend: OnSend
  private let onReceive: OnReceive

  init(
    onSend: @escaping OnSend = { part, promise, context in context.send(part, promise: promise) },
    onReceive: @escaping OnReceive = { part, context in context.receive(part) }
  ) {
    self.onSend = onSend
    self.onReceive = onReceive
  }

  override func send(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  ) {
    self.onSend(part, promise, context)
  }

  override func receive(
    _ part: GRPCClientResponsePart<Response>,
    context: ClientInterceptorContext<Request, Response>
  ) {
    self.onReceive(part, context)
  }
}

class DelegatingEchoClientInterceptorFactory: Echo_EchoClientInterceptorFactoryProtocol {
  typealias OnSend = DelegatingClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>.OnSend
  let interceptor: DelegatingClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>

  init(onSend: @escaping OnSend) {
    self.interceptor = DelegatingClientInterceptor(onSend: onSend)
  }

  func makeGetInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [self.interceptor]
  }

  func makeExpandInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [self.interceptor]
  }

  func makeCollectInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [self.interceptor]
  }

  func makeUpdateInterceptors() -> [ClientInterceptor<Echo_EchoRequest, Echo_EchoResponse>] {
    return [self.interceptor]
  }
}
