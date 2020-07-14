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
import NIOHTTP2
import NIOSSL
import SwiftProtobuf

public protocol GRPCChannel {
  /// Make a unary gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  func makeUnaryCall<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    path: String,
    request: Request,
    callOptions: CallOptions
  ) -> UnaryCall<Request, Response>

  /// Make a unary gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  func makeUnaryCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions
  ) -> UnaryCall<Request, Response>

  /// Make a server-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  ///   - handler: Response handler; called for every response received from the server.
  func makeServerStreamingCall<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    path: String,
    request: Request,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response>

  /// Make a server-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - request: The request to send.
  ///   - callOptions: Options for the RPC.
  ///   - handler: Response handler; called for every response received from the server.
  func makeServerStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response>

  /// Makes a client-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  func makeClientStreamingCall<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    path: String,
    callOptions: CallOptions
  ) -> ClientStreamingCall<Request, Response>

  /// Makes a client-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  func makeClientStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions
  ) -> ClientStreamingCall<Request, Response>

  /// Makes a bidirectional-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  ///   - handler: Response handler; called for every response received from the server.
  func makeBidirectionalStreamingCall<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    path: String,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response>

  /// Makes a bidirectional-streaming gRPC call.
  ///
  /// - Parameters:
  ///   - path: Path of the RPC, e.g. "/echo.Echo/Get"
  ///   - callOptions: Options for the RPC.
  ///   - handler: Response handler; called for every response received from the server.
  func makeBidirectionalStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response>

  /// Close the channel, and any connections associated with it.
  func close() -> EventLoopFuture<Void>
}
