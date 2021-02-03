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

import GRPC
import NIO
import SwiftProtobuf

final class NormalizationProvider: Normalization_NormalizationProvider {
  let interceptors: Normalization_NormalizationServerInterceptorFactoryProtocol? = nil

  // MARK: Unary

  private func unary(
    context: StatusOnlyCallContext,
    function: String = #function
  ) -> EventLoopFuture<Normalization_FunctionName> {
    return context.eventLoop.makeSucceededFuture(.with { $0.functionName = function })
  }

  func Unary(
    request: Google_Protobuf_Empty,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Normalization_FunctionName> {
    return self.unary(context: context)
  }

  func unary(
    request: Google_Protobuf_Empty,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Normalization_FunctionName> {
    return self.unary(context: context)
  }

  // MARK: Server Streaming

  private func serverStreaming(
    context: StreamingResponseCallContext<Normalization_FunctionName>,
    function: String = #function
  ) -> EventLoopFuture<GRPCStatus> {
    context.sendResponse(.with { $0.functionName = function }, promise: nil)
    return context.eventLoop.makeSucceededFuture(.ok)
  }

  func ServerStreaming(
    request: Google_Protobuf_Empty,
    context: StreamingResponseCallContext<Normalization_FunctionName>
  ) -> EventLoopFuture<GRPCStatus> {
    return self.serverStreaming(context: context)
  }

  func serverStreaming(
    request: Google_Protobuf_Empty,
    context: StreamingResponseCallContext<Normalization_FunctionName>
  ) -> EventLoopFuture<GRPCStatus> {
    return self.serverStreaming(context: context)
  }

  // MARK: Client Streaming

  private func _clientStreaming(
    context: UnaryResponseCallContext<Normalization_FunctionName>,
    function: String = #function
  ) -> EventLoopFuture<(StreamEvent<Google_Protobuf_Empty>) -> Void> {
    func handle(_ event: StreamEvent<Google_Protobuf_Empty>) {
      switch event {
      case .message:
        ()
      case .end:
        context.responsePromise.succeed(.with { $0.functionName = function })
      }
    }

    return context.eventLoop.makeSucceededFuture(handle(_:))
  }

  func ClientStreaming(
    context: UnaryResponseCallContext<Normalization_FunctionName>
  ) -> EventLoopFuture<(StreamEvent<Google_Protobuf_Empty>) -> Void> {
    return self._clientStreaming(context: context)
  }

  func clientStreaming(
    context: UnaryResponseCallContext<Normalization_FunctionName>
  ) -> EventLoopFuture<(StreamEvent<Google_Protobuf_Empty>) -> Void> {
    return self._clientStreaming(context: context)
  }

  // MARK: Bidirectional Streaming

  private func _bidirectionalStreaming(
    context: StreamingResponseCallContext<Normalization_FunctionName>,
    function: String = #function
  ) -> EventLoopFuture<(StreamEvent<Google_Protobuf_Empty>) -> Void> {
    func handle(_ event: StreamEvent<Google_Protobuf_Empty>) {
      switch event {
      case .message:
        ()
      case .end:
        context.sendResponse(.with { $0.functionName = function }, promise: nil)
        context.statusPromise.succeed(.ok)
      }
    }

    return context.eventLoop.makeSucceededFuture(handle(_:))
  }

  func BidirectionalStreaming(
    context: StreamingResponseCallContext<Normalization_FunctionName>
  ) -> EventLoopFuture<(StreamEvent<Google_Protobuf_Empty>) -> Void> {
    return self._bidirectionalStreaming(context: context)
  }

  func bidirectionalStreaming(
    context: StreamingResponseCallContext<Normalization_FunctionName>
  ) -> EventLoopFuture<(StreamEvent<Google_Protobuf_Empty>) -> Void> {
    return self._bidirectionalStreaming(context: context)
  }
}
