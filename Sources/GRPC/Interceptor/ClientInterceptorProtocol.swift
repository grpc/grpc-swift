/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIO

internal protocol ClientInterceptorProtocol {
  associatedtype Request
  associatedtype Response

  /// Called when the interceptor has received a response part to handle.
  func receive(
    _ part: GRPCClientResponsePart<Response>,
    context: ClientInterceptorContext<Request, Response>
  )

  /// Called when the interceptor has received a request part to handle.
  func send(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  )

  /// Called when the interceptor has received a request to cancel the RPC.
  func cancel(
    promise: EventLoopPromise<Void>?,
    context: ClientInterceptorContext<Request, Response>
  )
}
