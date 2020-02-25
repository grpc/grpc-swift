//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: src/proto/grpc/testing/test.proto
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


/// Usage: instantiate Grpc_Testing_TestServiceServiceClient, then call methods of this protocol to make API calls.
public protocol Grpc_Testing_TestServiceService {
  func emptyCall(_ request: Grpc_Testing_Empty, callOptions: CallOptions?) -> UnaryCall<Grpc_Testing_Empty, Grpc_Testing_Empty>
  func unaryCall(_ request: Grpc_Testing_SimpleRequest, callOptions: CallOptions?) -> UnaryCall<Grpc_Testing_SimpleRequest, Grpc_Testing_SimpleResponse>
  func cacheableUnaryCall(_ request: Grpc_Testing_SimpleRequest, callOptions: CallOptions?) -> UnaryCall<Grpc_Testing_SimpleRequest, Grpc_Testing_SimpleResponse>
  func streamingOutputCall(_ request: Grpc_Testing_StreamingOutputCallRequest, callOptions: CallOptions?, handler: @escaping (Grpc_Testing_StreamingOutputCallResponse) -> Void) -> ServerStreamingCall<Grpc_Testing_StreamingOutputCallRequest, Grpc_Testing_StreamingOutputCallResponse>
  func streamingInputCall(callOptions: CallOptions?) -> ClientStreamingCall<Grpc_Testing_StreamingInputCallRequest, Grpc_Testing_StreamingInputCallResponse>
  func fullDuplexCall(callOptions: CallOptions?, handler: @escaping (Grpc_Testing_StreamingOutputCallResponse) -> Void) -> BidirectionalStreamingCall<Grpc_Testing_StreamingOutputCallRequest, Grpc_Testing_StreamingOutputCallResponse>
  func halfDuplexCall(callOptions: CallOptions?, handler: @escaping (Grpc_Testing_StreamingOutputCallResponse) -> Void) -> BidirectionalStreamingCall<Grpc_Testing_StreamingOutputCallRequest, Grpc_Testing_StreamingOutputCallResponse>
  func unimplementedCall(_ request: Grpc_Testing_Empty, callOptions: CallOptions?) -> UnaryCall<Grpc_Testing_Empty, Grpc_Testing_Empty>
}

public final class Grpc_Testing_TestServiceServiceClient: GRPCClient, Grpc_Testing_TestServiceService {
  public let channel: GRPCChannel
  public var defaultCallOptions: CallOptions

  /// Creates a client for the grpc.testing.TestService service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  public init(channel: GRPCChannel, defaultCallOptions: CallOptions = CallOptions()) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
  }

  /// Asynchronous unary call to EmptyCall.
  ///
  /// - Parameters:
  ///   - request: Request to send to EmptyCall.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func emptyCall(_ request: Grpc_Testing_Empty, callOptions: CallOptions? = nil) -> UnaryCall<Grpc_Testing_Empty, Grpc_Testing_Empty> {
    return self.makeUnaryCall(path: "/grpc.testing.TestService/EmptyCall",
                              request: request,
                              callOptions: callOptions ?? self.defaultCallOptions)
  }

  /// Asynchronous unary call to UnaryCall.
  ///
  /// - Parameters:
  ///   - request: Request to send to UnaryCall.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func unaryCall(_ request: Grpc_Testing_SimpleRequest, callOptions: CallOptions? = nil) -> UnaryCall<Grpc_Testing_SimpleRequest, Grpc_Testing_SimpleResponse> {
    return self.makeUnaryCall(path: "/grpc.testing.TestService/UnaryCall",
                              request: request,
                              callOptions: callOptions ?? self.defaultCallOptions)
  }

  /// Asynchronous unary call to CacheableUnaryCall.
  ///
  /// - Parameters:
  ///   - request: Request to send to CacheableUnaryCall.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func cacheableUnaryCall(_ request: Grpc_Testing_SimpleRequest, callOptions: CallOptions? = nil) -> UnaryCall<Grpc_Testing_SimpleRequest, Grpc_Testing_SimpleResponse> {
    return self.makeUnaryCall(path: "/grpc.testing.TestService/CacheableUnaryCall",
                              request: request,
                              callOptions: callOptions ?? self.defaultCallOptions)
  }

  /// Asynchronous server-streaming call to StreamingOutputCall.
  ///
  /// - Parameters:
  ///   - request: Request to send to StreamingOutputCall.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ServerStreamingCall` with futures for the metadata and status.
  public func streamingOutputCall(_ request: Grpc_Testing_StreamingOutputCallRequest, callOptions: CallOptions? = nil, handler: @escaping (Grpc_Testing_StreamingOutputCallResponse) -> Void) -> ServerStreamingCall<Grpc_Testing_StreamingOutputCallRequest, Grpc_Testing_StreamingOutputCallResponse> {
    return self.makeServerStreamingCall(path: "/grpc.testing.TestService/StreamingOutputCall",
                                        request: request,
                                        callOptions: callOptions ?? self.defaultCallOptions,
                                        handler: handler)
  }

  /// Asynchronous client-streaming call to StreamingInputCall.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `ClientStreamingCall` with futures for the metadata, status and response.
  public func streamingInputCall(callOptions: CallOptions? = nil) -> ClientStreamingCall<Grpc_Testing_StreamingInputCallRequest, Grpc_Testing_StreamingInputCallResponse> {
    return self.makeClientStreamingCall(path: "/grpc.testing.TestService/StreamingInputCall",
                                        callOptions: callOptions ?? self.defaultCallOptions)
  }

  /// Asynchronous bidirectional-streaming call to FullDuplexCall.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ClientStreamingCall` with futures for the metadata and status.
  public func fullDuplexCall(callOptions: CallOptions? = nil, handler: @escaping (Grpc_Testing_StreamingOutputCallResponse) -> Void) -> BidirectionalStreamingCall<Grpc_Testing_StreamingOutputCallRequest, Grpc_Testing_StreamingOutputCallResponse> {
    return self.makeBidirectionalStreamingCall(path: "/grpc.testing.TestService/FullDuplexCall",
                                               callOptions: callOptions ?? self.defaultCallOptions,
                                               handler: handler)
  }

  /// Asynchronous bidirectional-streaming call to HalfDuplexCall.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ClientStreamingCall` with futures for the metadata and status.
  public func halfDuplexCall(callOptions: CallOptions? = nil, handler: @escaping (Grpc_Testing_StreamingOutputCallResponse) -> Void) -> BidirectionalStreamingCall<Grpc_Testing_StreamingOutputCallRequest, Grpc_Testing_StreamingOutputCallResponse> {
    return self.makeBidirectionalStreamingCall(path: "/grpc.testing.TestService/HalfDuplexCall",
                                               callOptions: callOptions ?? self.defaultCallOptions,
                                               handler: handler)
  }

  /// Asynchronous unary call to UnimplementedCall.
  ///
  /// - Parameters:
  ///   - request: Request to send to UnimplementedCall.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func unimplementedCall(_ request: Grpc_Testing_Empty, callOptions: CallOptions? = nil) -> UnaryCall<Grpc_Testing_Empty, Grpc_Testing_Empty> {
    return self.makeUnaryCall(path: "/grpc.testing.TestService/UnimplementedCall",
                              request: request,
                              callOptions: callOptions ?? self.defaultCallOptions)
  }

}

/// Usage: instantiate Grpc_Testing_UnimplementedServiceServiceClient, then call methods of this protocol to make API calls.
public protocol Grpc_Testing_UnimplementedServiceService {
  func unimplementedCall(_ request: Grpc_Testing_Empty, callOptions: CallOptions?) -> UnaryCall<Grpc_Testing_Empty, Grpc_Testing_Empty>
}

public final class Grpc_Testing_UnimplementedServiceServiceClient: GRPCClient, Grpc_Testing_UnimplementedServiceService {
  public let channel: GRPCChannel
  public var defaultCallOptions: CallOptions

  /// Creates a client for the grpc.testing.UnimplementedService service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  public init(channel: GRPCChannel, defaultCallOptions: CallOptions = CallOptions()) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
  }

  /// Asynchronous unary call to UnimplementedCall.
  ///
  /// - Parameters:
  ///   - request: Request to send to UnimplementedCall.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func unimplementedCall(_ request: Grpc_Testing_Empty, callOptions: CallOptions? = nil) -> UnaryCall<Grpc_Testing_Empty, Grpc_Testing_Empty> {
    return self.makeUnaryCall(path: "/grpc.testing.UnimplementedService/UnimplementedCall",
                              request: request,
                              callOptions: callOptions ?? self.defaultCallOptions)
  }

}

/// Usage: instantiate Grpc_Testing_ReconnectServiceServiceClient, then call methods of this protocol to make API calls.
public protocol Grpc_Testing_ReconnectServiceService {
  func start(_ request: Grpc_Testing_ReconnectParams, callOptions: CallOptions?) -> UnaryCall<Grpc_Testing_ReconnectParams, Grpc_Testing_Empty>
  func stop(_ request: Grpc_Testing_Empty, callOptions: CallOptions?) -> UnaryCall<Grpc_Testing_Empty, Grpc_Testing_ReconnectInfo>
}

public final class Grpc_Testing_ReconnectServiceServiceClient: GRPCClient, Grpc_Testing_ReconnectServiceService {
  public let channel: GRPCChannel
  public var defaultCallOptions: CallOptions

  /// Creates a client for the grpc.testing.ReconnectService service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  public init(channel: GRPCChannel, defaultCallOptions: CallOptions = CallOptions()) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
  }

  /// Asynchronous unary call to Start.
  ///
  /// - Parameters:
  ///   - request: Request to send to Start.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func start(_ request: Grpc_Testing_ReconnectParams, callOptions: CallOptions? = nil) -> UnaryCall<Grpc_Testing_ReconnectParams, Grpc_Testing_Empty> {
    return self.makeUnaryCall(path: "/grpc.testing.ReconnectService/Start",
                              request: request,
                              callOptions: callOptions ?? self.defaultCallOptions)
  }

  /// Asynchronous unary call to Stop.
  ///
  /// - Parameters:
  ///   - request: Request to send to Stop.
  ///   - callOptions: Call options; `self.defaultCallOptions` is used if `nil`.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func stop(_ request: Grpc_Testing_Empty, callOptions: CallOptions? = nil) -> UnaryCall<Grpc_Testing_Empty, Grpc_Testing_ReconnectInfo> {
    return self.makeUnaryCall(path: "/grpc.testing.ReconnectService/Stop",
                              request: request,
                              callOptions: callOptions ?? self.defaultCallOptions)
  }

}

/// To build a server, implement a class that conforms to this protocol.
public protocol Grpc_Testing_TestServiceProvider: CallHandlerProvider {
  func emptyCall(request: Grpc_Testing_Empty, context: StatusOnlyCallContext) -> EventLoopFuture<Grpc_Testing_Empty>
  func unaryCall(request: Grpc_Testing_SimpleRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Grpc_Testing_SimpleResponse>
  func cacheableUnaryCall(request: Grpc_Testing_SimpleRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Grpc_Testing_SimpleResponse>
  func streamingOutputCall(request: Grpc_Testing_StreamingOutputCallRequest, context: StreamingResponseCallContext<Grpc_Testing_StreamingOutputCallResponse>) -> EventLoopFuture<GRPCStatus>
  func streamingInputCall(context: UnaryResponseCallContext<Grpc_Testing_StreamingInputCallResponse>) -> EventLoopFuture<(StreamEvent<Grpc_Testing_StreamingInputCallRequest>) -> Void>
  func fullDuplexCall(context: StreamingResponseCallContext<Grpc_Testing_StreamingOutputCallResponse>) -> EventLoopFuture<(StreamEvent<Grpc_Testing_StreamingOutputCallRequest>) -> Void>
  func halfDuplexCall(context: StreamingResponseCallContext<Grpc_Testing_StreamingOutputCallResponse>) -> EventLoopFuture<(StreamEvent<Grpc_Testing_StreamingOutputCallRequest>) -> Void>
}

extension Grpc_Testing_TestServiceProvider {
  public var serviceName: String { return "grpc.testing.TestService" }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  public func handleMethod(_ methodName: String, callHandlerContext: CallHandlerContext) -> GRPCCallHandler? {
    switch methodName {
    case "EmptyCall":
      return UnaryCallHandler(callHandlerContext: callHandlerContext) { context in
        return { request in
          self.emptyCall(request: request, context: context)
        }
      }

    case "UnaryCall":
      return UnaryCallHandler(callHandlerContext: callHandlerContext) { context in
        return { request in
          self.unaryCall(request: request, context: context)
        }
      }

    case "CacheableUnaryCall":
      return UnaryCallHandler(callHandlerContext: callHandlerContext) { context in
        return { request in
          self.cacheableUnaryCall(request: request, context: context)
        }
      }

    case "StreamingOutputCall":
      return ServerStreamingCallHandler(callHandlerContext: callHandlerContext) { context in
        return { request in
          self.streamingOutputCall(request: request, context: context)
        }
      }

    case "StreamingInputCall":
      return ClientStreamingCallHandler(callHandlerContext: callHandlerContext) { context in
        return self.streamingInputCall(context: context)
      }

    case "FullDuplexCall":
      return BidirectionalStreamingCallHandler(callHandlerContext: callHandlerContext) { context in
        return self.fullDuplexCall(context: context)
      }

    case "HalfDuplexCall":
      return BidirectionalStreamingCallHandler(callHandlerContext: callHandlerContext) { context in
        return self.halfDuplexCall(context: context)
      }

    default: return nil
    }
  }
}

/// To build a server, implement a class that conforms to this protocol.
public protocol Grpc_Testing_UnimplementedServiceProvider: CallHandlerProvider {
  func unimplementedCall(request: Grpc_Testing_Empty, context: StatusOnlyCallContext) -> EventLoopFuture<Grpc_Testing_Empty>
}

extension Grpc_Testing_UnimplementedServiceProvider {
  public var serviceName: String { return "grpc.testing.UnimplementedService" }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  public func handleMethod(_ methodName: String, callHandlerContext: CallHandlerContext) -> GRPCCallHandler? {
    switch methodName {
    case "UnimplementedCall":
      return UnaryCallHandler(callHandlerContext: callHandlerContext) { context in
        return { request in
          self.unimplementedCall(request: request, context: context)
        }
      }

    default: return nil
    }
  }
}

/// To build a server, implement a class that conforms to this protocol.
public protocol Grpc_Testing_ReconnectServiceProvider: CallHandlerProvider {
  func start(request: Grpc_Testing_ReconnectParams, context: StatusOnlyCallContext) -> EventLoopFuture<Grpc_Testing_Empty>
  func stop(request: Grpc_Testing_Empty, context: StatusOnlyCallContext) -> EventLoopFuture<Grpc_Testing_ReconnectInfo>
}

extension Grpc_Testing_ReconnectServiceProvider {
  public var serviceName: String { return "grpc.testing.ReconnectService" }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  public func handleMethod(_ methodName: String, callHandlerContext: CallHandlerContext) -> GRPCCallHandler? {
    switch methodName {
    case "Start":
      return UnaryCallHandler(callHandlerContext: callHandlerContext) { context in
        return { request in
          self.start(request: request, context: context)
        }
      }

    case "Stop":
      return UnaryCallHandler(callHandlerContext: callHandlerContext) { context in
        return { request in
          self.stop(request: request, context: context)
        }
      }

    default: return nil
    }
  }
}


/// Provides conformance to `GRPCPayload` for the request and response messages
extension Grpc_Testing_Empty: GRPCProtobufPayload {}
extension Grpc_Testing_SimpleRequest: GRPCProtobufPayload {}
extension Grpc_Testing_SimpleResponse: GRPCProtobufPayload {}
extension Grpc_Testing_StreamingOutputCallRequest: GRPCProtobufPayload {}
extension Grpc_Testing_StreamingOutputCallResponse: GRPCProtobufPayload {}
extension Grpc_Testing_StreamingInputCallRequest: GRPCProtobufPayload {}
extension Grpc_Testing_StreamingInputCallResponse: GRPCProtobufPayload {}


extension Grpc_Testing_ReconnectParams: GRPCProtobufPayload {}
extension Grpc_Testing_ReconnectInfo: GRPCProtobufPayload {}

