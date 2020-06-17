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


/// Usage: instantiate Echo_EchoClient, then call methods of this protocol to make API calls.
public protocol Echo_EchoClientProtocol: GRPCClient {
  func get(
    _ request: Echo_EchoRequest,
    callOptions: CallOptions
  ) -> UnaryCall<Echo_EchoRequest, Echo_EchoResponse>

  func expand(
    _ request: Echo_EchoRequest,
    callOptions: CallOptions,
    handler: @escaping (Echo_EchoResponse) -> Void
  ) -> ServerStreamingCall<Echo_EchoRequest, Echo_EchoResponse>

  func collect(
    callOptions: CallOptions
  ) -> ClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse>

  func update(
    callOptions: CallOptions,
    handler: @escaping (Echo_EchoResponse) -> Void
  ) -> BidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse>

}

extension Echo_EchoClientProtocol {
  public func get(
    _ request: Echo_EchoRequest
  ) -> UnaryCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.get(request, callOptions: self.defaultCallOptions)
  }

  public func expand(
    _ request: Echo_EchoRequest,
    handler: @escaping (Echo_EchoResponse) -> Void
  ) -> ServerStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.expand(request, callOptions: self.defaultCallOptions, handler: handler)
  }

  public func collect() -> ClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.collect(callOptions: self.defaultCallOptions)
  }

  public func update(
    handler: @escaping (Echo_EchoResponse) -> Void
  ) -> BidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.update(callOptions: self.defaultCallOptions, handler: handler)
  }

}

public final class Echo_EchoClient: Echo_EchoClientProtocol {
  public let channel: GRPCChannel
  public var defaultCallOptions: CallOptions

  /// Creates a client for the echo.Echo service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  public init(channel: GRPCChannel, defaultCallOptions: CallOptions = CallOptions()) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
  }

  /// Immediately returns an echo of a request.
  ///
  /// - Parameters:
  ///   - request: Request to send to Get.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func get(
    _ request: Echo_EchoRequest,
    callOptions: CallOptions
  ) -> UnaryCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeUnaryCall(
      path: "/echo.Echo/Get",
      request: request,
      callOptions: callOptions
    )
  }

  /// Splits a request into words and returns each word in a stream of messages.
  ///
  /// - Parameters:
  ///   - request: Request to send to Expand.
  ///   - callOptions: Call options.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ServerStreamingCall` with futures for the metadata and status.
  public func expand(
    _ request: Echo_EchoRequest,
    callOptions: CallOptions,
    handler: @escaping (Echo_EchoResponse) -> Void
  ) -> ServerStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeServerStreamingCall(
      path: "/echo.Echo/Expand",
      request: request,
      callOptions: callOptions,
      handler: handler
    )
  }

  /// Collects a stream of messages and returns them concatenated when the caller closes.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options.
  /// - Returns: A `ClientStreamingCall` with futures for the metadata, status and response.
  public func collect(
    callOptions: CallOptions
  ) -> ClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeClientStreamingCall(
      path: "/echo.Echo/Collect",
      callOptions: callOptions
    )
  }

  /// Streams back messages as they are received in an input stream.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ClientStreamingCall` with futures for the metadata and status.
  public func update(
    callOptions: CallOptions,
    handler: @escaping (Echo_EchoResponse) -> Void
  ) -> BidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeBidirectionalStreamingCall(
      path: "/echo.Echo/Update",
      callOptions: callOptions,
      handler: handler
    )
  }
}

public final class Echo_EchoTestClient: Echo_EchoClientProtocol {
  private let fakeChannel: FakeChannel
  public var defaultCallOptions: CallOptions

  public var channel: GRPCChannel {
    return self.fakeChannel
  }

  public init(
    fakeChannel: FakeChannel = FakeChannel(),
    defaultCallOptions callOptions: CallOptions = CallOptions()
  ) {
    self.fakeChannel = fakeChannel
    self.defaultCallOptions = callOptions
  }

  /// Immediately returns an echo of a request.
  ///
  /// - Parameters:
  ///   - request: Request to send to Get.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func get(
    _ request: Echo_EchoRequest,
    callOptions: CallOptions
  ) -> UnaryCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeUnaryCall(
      path: "/echo.Echo/Get",
      request: request,
      callOptions: callOptions
    )
  }

  /// Splits a request into words and returns each word in a stream of messages.
  ///
  /// - Parameters:
  ///   - request: Request to send to Expand.
  ///   - callOptions: Call options.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ServerStreamingCall` with futures for the metadata and status.
  public func expand(
    _ request: Echo_EchoRequest,
    callOptions: CallOptions,
    handler: @escaping (Echo_EchoResponse) -> Void
  ) -> ServerStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeServerStreamingCall(
      path: "/echo.Echo/Expand",
      request: request,
      callOptions: callOptions,
      handler: handler
    )
  }

  /// Collects a stream of messages and returns them concatenated when the caller closes.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options.
  /// - Returns: A `ClientStreamingCall` with futures for the metadata, status and response.
  public func collect(
    callOptions: CallOptions
  ) -> ClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeClientStreamingCall(
      path: "/echo.Echo/Collect",
      callOptions: callOptions
    )
  }

  /// Streams back messages as they are received in an input stream.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ClientStreamingCall` with futures for the metadata and status.
  public func update(
    callOptions: CallOptions,
    handler: @escaping (Echo_EchoResponse) -> Void
  ) -> BidirectionalStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    return self.makeBidirectionalStreamingCall(
      path: "/echo.Echo/Update",
      callOptions: callOptions,
      handler: handler
    )
  }

  /// Make a unary response for the Get RPC. This must be called
  /// before calling 'get'. See also 'FakeUnaryResponse'.
  ///
  /// - Parameter requestHandler: a handler for request parts sent by the RPC.
  public func makeGetResponseStream(
    _ requestHandler: @escaping (FakeRequestPart<Echo_EchoRequest>) -> () = { _ in }
  ) -> FakeUnaryResponse<Echo_EchoRequest, Echo_EchoResponse> {
    self.fakeChannel.makeFakeUnaryResponse(path: "/echo.Echo/Get", requestHandler: requestHandler)
  }

  /// Make a streaming response for the Expand RPC. This must be called
  /// before calling 'expand'. See also 'FakeStreamingResponse'.
  ///
  /// - Parameter requestHandler: a handler for request parts sent by the RPC.
  public func makeExpandResponseStream(
    _ requestHandler: @escaping (FakeRequestPart<Echo_EchoRequest>) -> () = { _ in }
  ) -> FakeStreamingResponse<Echo_EchoRequest, Echo_EchoResponse> {
    self.fakeChannel.makeFakeStreamingResponse(path: "/echo.Echo/Expand", requestHandler: requestHandler)
  }

  /// Make a unary response for the Collect RPC. This must be called
  /// before calling 'collect'. See also 'FakeUnaryResponse'.
  ///
  /// - Parameter requestHandler: a handler for request parts sent by the RPC.
  public func makeCollectResponseStream(
    _ requestHandler: @escaping (FakeRequestPart<Echo_EchoRequest>) -> () = { _ in }
  ) -> FakeUnaryResponse<Echo_EchoRequest, Echo_EchoResponse> {
    self.fakeChannel.makeFakeUnaryResponse(path: "/echo.Echo/Collect", requestHandler: requestHandler)
  }

  /// Make a streaming response for the Update RPC. This must be called
  /// before calling 'update'. See also 'FakeStreamingResponse'.
  ///
  /// - Parameter requestHandler: a handler for request parts sent by the RPC.
  public func makeUpdateResponseStream(
    _ requestHandler: @escaping (FakeRequestPart<Echo_EchoRequest>) -> () = { _ in }
  ) -> FakeStreamingResponse<Echo_EchoRequest, Echo_EchoResponse> {
    self.fakeChannel.makeFakeStreamingResponse(path: "/echo.Echo/Update", requestHandler: requestHandler)
  }
}

/// To build a server, implement a class that conforms to this protocol.
public protocol Echo_EchoProvider: CallHandlerProvider {
  /// Immediately returns an echo of a request.
  func get(request: Echo_EchoRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Echo_EchoResponse>
  /// Splits a request into words and returns each word in a stream of messages.
  func expand(request: Echo_EchoRequest, context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<GRPCStatus>
  /// Collects a stream of messages and returns them concatenated when the caller closes.
  func collect(context: UnaryResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void>
  /// Streams back messages as they are received in an input stream.
  func update(context: StreamingResponseCallContext<Echo_EchoResponse>) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void>
}

extension Echo_EchoProvider {
  public var serviceName: String { return "echo.Echo" }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  public func handleMethod(_ methodName: String, callHandlerContext: CallHandlerContext) -> GRPCCallHandler? {
    switch methodName {
    case "Get":
      return UnaryCallHandler(callHandlerContext: callHandlerContext) { context in
        return { request in
          self.get(request: request, context: context)
        }
      }

    case "Expand":
      return ServerStreamingCallHandler(callHandlerContext: callHandlerContext) { context in
        return { request in
          self.expand(request: request, context: context)
        }
      }

    case "Collect":
      return ClientStreamingCallHandler(callHandlerContext: callHandlerContext) { context in
        return self.collect(context: context)
      }

    case "Update":
      return BidirectionalStreamingCallHandler(callHandlerContext: callHandlerContext) { context in
        return self.update(context: context)
      }

    default: return nil
    }
  }
}


// Provides conformance to `GRPCPayload`
extension Echo_EchoRequest: GRPCProtobufPayload {}
extension Echo_EchoResponse: GRPCProtobufPayload {}
