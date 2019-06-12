//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: echo.proto
//

//
// Copyright 2018, gRPC Authors All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
import Foundation
import GRPC
import NIO
import NIOHTTP1
import SwiftProtobuf


/// Usage: instantiate Echo_EchoServiceClient, then call methods of this protocol to make API calls.
internal protocol Echo_EchoService {
  func get(_ request: Echo_EchoRequest, callOptions: CallOptions?) -> UnaryCall<Echo_EchoRequest, Echo_EchoResponse>
  func expand(_ request: Echo_EchoRequest, callOptions: CallOptions?, handler: @escaping (Echo_EchoResponse) -> Void) -> ServerStreamingCall<Echo_EchoRequest, Echo_EchoResponse>
  func collect(callOptions: CallOptions?) -> ClientStreamingClientCall<Echo_EchoRequest, Echo_EchoResponse>
  func update(callOptions: CallOptions?, handler: @escaping (Echo_EchoResponse) -> Void) -> BidirectionalStreamingClientCall<Echo_EchoRequest, Echo_EchoResponse>
}

internal final class Echo_EchoServiceClient: GRPCServiceClient, Echo_EchoService {
  internal let connection: ClientConnection
  internal var serviceName: String { return "echo.Echo" }
  internal var defaultCallOptions: CallOptions

  /// Creates a client for the echo.Echo service.
  ///
  /// - Parameters:
  ///   - connection: `ClientConnection` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  internal init(connection: ClientConnection, defaultCallOptions: CallOptions = CallOptions()) {
    self.connection = connection
    self.defaultCallOptions = defaultCallOptions
  }

  /// Asynchronous unary call to Get.
  ///
  /// - Parameters:
  ///   - request: Request to send to Get.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  internal func get(_ request: Echo_EchoRequest, callOptions: CallOptions? = nil) -> UnaryCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeUnaryCall(path: self.path(forMethod: "Get"),
                              request: request,
                              callOptions: callOptions ?? self.defaultCallOptions)
  }

  /// Asynchronous server-streaming call to Expand.
  ///
  /// - Parameters:
  ///   - request: Request to send to Expand.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ServerStreamingCall` with futures for the metadata and status.
  internal func expand(_ request: Echo_EchoRequest, callOptions: CallOptions? = nil, handler: @escaping (Echo_EchoResponse) -> Void) -> ServerStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeServerStreamingCall(path: self.path(forMethod: "Expand"),
                                        request: request,
                                        callOptions: callOptions ?? self.defaultCallOptions,
                                        handler: handler)
  }

  /// Asynchronous client-streaming call to Collect.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `ClientStreamingClientCall` with futures for the metadata, status and response.
  internal func collect(callOptions: CallOptions? = nil) -> ClientStreamingClientCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeClientStreamingCall(path: self.path(forMethod: "Collect"),
                                        callOptions: callOptions ?? self.defaultCallOptions)
  }

  /// Asynchronous bidirectional-streaming call to Update.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ClientStreamingClientCall` with futures for the metadata and status.
  internal func update(callOptions: CallOptions? = nil, handler: @escaping (Echo_EchoResponse) -> Void) -> BidirectionalStreamingClientCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeBidirectionalStreamingCall(path: self.path(forMethod: "Update"),
                                               callOptions: callOptions ?? self.defaultCallOptions,
                                               handler: handler)
  }

}

/// To build a server, implement a class that conforms to this protocol.
internal protocol Echo_EchoProvider: CallHandlerProvider {
  func get(request: Echo_EchoRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Echo_EchoResponse>
  func expand(request: Echo_EchoRequest, context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<GRPCStatus>
  func collect(context: UnaryResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void>
  func update(context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void>
}

extension Echo_EchoProvider {
  internal var serviceName: String { return "echo.Echo" }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  internal func handleMethod(_ methodName: String, request: HTTPRequestHead, serverHandler: GRPCChannelHandler, channel: Channel, errorDelegate: ServerErrorDelegate?) -> GRPCCallHandler? {
    switch methodName {
    case "Get":
      return UnaryCallHandler(channel: channel, request: request, errorDelegate: errorDelegate) { context in
        return { request in
          self.get(request: request, context: context)
        }
      }

    case "Expand":
      return ServerStreamingCallHandler(channel: channel, request: request, errorDelegate: errorDelegate) { context in
        return { request in
          self.expand(request: request, context: context)
        }
      }

    case "Collect":
      return ClientStreamingCallHandler(channel: channel, request: request, errorDelegate: errorDelegate) { context in
        return self.collect(context: context)
      }

    case "Update":
      return BidirectionalStreamingCallHandler(channel: channel, request: request, errorDelegate: errorDelegate) { context in
        return self.update(context: context)
      }

    default: return nil
    }
  }
}

